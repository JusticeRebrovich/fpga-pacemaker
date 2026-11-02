`timescale 1ns/1ps
//==============================================================================
// tb_pacemaker.sv : self-checking testbench for pacemaker_core
//
// Three independent layers of checking:
//   1. Reference model  : a behavioral copy of the LIF detectors and controller,
//                         compared with the DUT outputs on every sample tick.
//   2. Protocol checks  : rules checked on the DUT outputs alone (lower rate,
//                         AV delay, PVARP, VRP, exclusivity). They do not use
//                         the model, so they catch bugs the model shares.
//   3. Directed tests   : scenarios with hand-computed expected event counts.
//
// Run in Vivado: add rtl/pacemaker.v and this file, set tb_pacemaker as the
// simulation top, and run all. Prints "TEST PASSED" or "TEST FAILED".
// Plusargs (xsim -testplusarg): TEST=directed|random|all  (default all)
// Seed the random test with: xsim -sv_seed N
//==============================================================================
module tb_pacemaker;

    // ---- must match the RTL defaults ----------------------------------------
    localparam integer LRI    = 1000;
    localparam integer AV     = 150;
    localparam integer PVARP  = 250;
    localparam integer VRP    = 200;
    localparam integer ABLANK = 40;
    localparam integer XBLANK = 20;
    localparam integer VA     = LRI - AV;
    localparam integer BASE   = 2048;
    localparam integer GAIN = 40, DZ = 100, LEAK = 4, TH_BASE = 1536, TH_INC = 128,
                       TH_MAX = 8192, TAU = 5, LIF_REFRACT = 3;
    localparam integer ACC_MAX = (1 << 19) - 1;
    localparam integer ACC_MIN = -(1 << 19);
    localparam integer TICK_CLKS = 4;       // clocks per sample tick in simulation

    // ---- DUT -----------------------------------------------------------------
    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         en  = 1'b0;
    reg  [11:0] a_s = 12'd2048, v_s = 12'd2048;
    wire        a_sense, a_pace, v_sense, v_pace, a_spike, v_spike;

    pacemaker_core dut (
        .clk(clk), .rst(rst), .sample_clk_en(en), .a_sample(a_s), .v_sample(v_s),
        .a_sense(a_sense), .a_pace(a_pace), .v_sense(v_sense), .v_pace(v_pace),
        .a_spike(a_spike), .v_spike(v_spike)
    );
    always #5 clk = ~clk;

    // ---- bookkeeping ---------------------------------------------------------
    integer errors = 0, checks = 0, tick_no = 0;
    integer cnt_as, cnt_ap, cnt_vs, cnt_vp;             // per test
    integer tot_as = 0, tot_ap = 0, tot_vs = 0, tot_vp = 0, blk_a = 0, blk_v = 0;
    integer noise_amp = 0;

    task err(input string id, input string msg);
        begin
            errors = errors + 1;
            if (errors <= 25) $display("ERROR [%s] tick=%0d %s", id, tick_no, msg);
        end
    endtask

    // ---- reference model -----------------------------------------------------
    integer m_v [0:1];
    integer m_th[0:1];
    integer m_rf[0:1];
    reg     m_spk[0:1];
    integer m_sv, m_sa, m_vrp, m_pvarp, m_abl, m_xbl;
    reg     m_await, m_avact;
    reg     m_as, m_ap, m_vs, m_vp;

    task model_reset;
        begin
            m_v[0] = 0; m_v[1] = 0; m_th[0] = TH_BASE; m_th[1] = TH_BASE;
            m_rf[0] = 0; m_rf[1] = 0; m_spk[0] = 0; m_spk[1] = 0;
            m_sv = 0; m_sa = 0; m_vrp = 0; m_pvarp = 0; m_abl = 0; m_xbl = 0;
            m_await = 1; m_avact = 0;
            m_as = 0; m_ap = 0; m_vs = 0; m_vp = 0;
        end
    endtask

    task model_lif(input integer ch, input integer smp);
        integer c, drv, vn;
        begin
            m_spk[ch] = 0;
            if (m_rf[ch] != 0) begin
                m_rf[ch] = m_rf[ch] - 1;
            end else begin
                c = smp - BASE;
                if (c > DZ || c < -DZ) drv = c * GAIN; else drv = 0;
                vn = m_v[ch] + drv - (m_v[ch] >>> LEAK);
                if (vn > ACC_MAX) vn = ACC_MAX; else if (vn < ACC_MIN) vn = ACC_MIN;
                if (vn >= m_th[ch]) begin
                    m_spk[ch] = 1; m_v[ch] = 0; m_rf[ch] = LIF_REFRACT;
                    m_th[ch] = (m_th[ch] + TH_INC > TH_MAX) ? TH_MAX : m_th[ch] + TH_INC;
                end else begin
                    m_v[ch]  = vn;
                    m_th[ch] = m_th[ch] - ((m_th[ch] - TH_BASE) >>> TAU);
                end
            end
        end
    endtask

    task model_ctrl;
        integer va_n, av_n;
        reg vs_ok, as_ok, ap_due, vp_due;
        begin
            m_as = 0; m_ap = 0; m_vs = 0; m_vp = 0;
            va_n = (m_sv >= 65535) ? 65535 : m_sv + 1;
            av_n = (m_sa >= 65535) ? 65535 : m_sa + 1;
            vs_ok  = m_spk[1] && (m_vrp == 0) && (m_xbl == 0);
            as_ok  = m_spk[0] && m_await && (m_pvarp == 0) && (m_abl == 0);
            ap_due = m_await  && (va_n >= VA);
            vp_due = m_avact  && (av_n >= AV);
            m_sv = va_n; m_sa = av_n;
            if (m_vrp > 0) m_vrp = m_vrp - 1;
            if (m_pvarp > 0) m_pvarp = m_pvarp - 1;
            if (m_abl > 0) m_abl = m_abl - 1;
            if (m_xbl > 0) m_xbl = m_xbl - 1;
            if (vs_ok || vp_due) begin
                m_vs = vs_ok; m_vp = !vs_ok;
                m_sv = 0; m_await = 1; m_avact = 0; m_vrp = VRP; m_pvarp = PVARP;
            end else if (as_ok || ap_due) begin
                m_as = as_ok; m_ap = !as_ok;
                m_await = 0; m_avact = 1; m_sa = 0;
                if (!as_ok) begin m_abl = ABLANK; m_xbl = XBLANK; end
            end
        end
    endtask

    // ---- protocol monitor state ----------------------------------------------
    integer last_v_tick, last_a_tick;
    reg     v_seen, last_v_was_pace, last_a_was_pace, a_ev_since_v;

    task monitor_reset;
        begin
            tick_no = 0; last_v_tick = 0; last_a_tick = 0; v_seen = 0;
            last_v_was_pace = 0; last_a_was_pace = 0; a_ev_since_v = 0;
            cnt_as = 0; cnt_ap = 0; cnt_vs = 0; cnt_vp = 0;
        end
    endtask

    task check_tick;
        reg a_ev, v_ev;
        begin
            checks = checks + 1;
            // 1. reference model
            if ({a_sense, a_pace, v_sense, v_pace} !== {m_as, m_ap, m_vs, m_vp})
                err("MODEL", $sformatf("DUT AS/AP/VS/VP=%b%b%b%b model=%b%b%b%b",
                    a_sense, a_pace, v_sense, v_pace, m_as, m_ap, m_vs, m_vp));
            if ({a_spike, v_spike} !== {m_spk[0], m_spk[1]})
                err("MODEL_LIF", $sformatf("DUT spikes A/V=%b%b model=%b%b",
                    a_spike, v_spike, m_spk[0], m_spk[1]));

            // 2. protocol checks on DUT outputs only
            a_ev = a_sense | a_pace;
            v_ev = v_sense | v_pace;
            if ((a_sense & a_pace) | (v_sense & v_pace) | (a_ev & v_ev))
                err("EXCLUSIVE", "more than one pacing event in one tick");
            if (a_spike & ~a_sense & ~a_pace) blk_a = blk_a + 1;
            if (v_spike & ~v_sense & ~v_pace) blk_v = blk_v + 1;

            if (a_ev) begin
                if (a_pace && (tick_no - last_v_tick != VA))
                    err("AP_TIMING", $sformatf("AP %0d ticks after V event, expected %0d",
                        tick_no - last_v_tick, VA));
                if (a_sense && v_seen && (tick_no - last_v_tick <= PVARP))
                    err("PVARP", $sformatf("AS %0d ticks after V event, inside PVARP",
                        tick_no - last_v_tick));
                if (a_ev_since_v)
                    err("A_TWICE", "second atrial event without a ventricular event");
                last_a_tick = tick_no; a_ev_since_v = 1; last_a_was_pace = a_pace;
                if (a_sense) cnt_as = cnt_as + 1; else cnt_ap = cnt_ap + 1;
            end
            if (v_ev) begin
                if (v_sense && v_seen && (tick_no - last_v_tick <= VRP))
                    err("VRP", $sformatf("VS %0d ticks after V event, inside VRP",
                        tick_no - last_v_tick));
                if (v_pace && (!a_ev_since_v || (tick_no - last_a_tick != AV)))
                    err("VP_TIMING", $sformatf("VP %0d ticks after atrial event, expected %0d",
                        tick_no - last_a_tick, AV));
                if (v_pace && last_v_was_pace && last_a_was_pace && (tick_no - last_v_tick != LRI))
                    err("PACED_RATE", $sformatf("paced V-V interval %0d, expected %0d",
                        tick_no - last_v_tick, LRI));
                last_v_tick = tick_no; v_seen = 1; last_v_was_pace = v_pace; a_ev_since_v = 0;
                if (v_sense) cnt_vs = cnt_vs + 1; else cnt_vp = cnt_vp + 1;
            end
            if (tick_no - last_v_tick > LRI)
                err("LOWER_RATE", $sformatf("%0d ticks without a ventricular event", tick_no - last_v_tick));
        end
    endtask

    // ---- stimulus primitives -------------------------------------------------
    task reset_dut;
        begin
            en = 0; rst = 1;
            repeat (3) @(negedge clk);
            rst = 0;
            model_reset; monitor_reset; noise_amp = 0;
        end
    endtask

    // one sample tick: DUT processes on the posedge between the two negedges
    task tick(input integer a, input integer v);
        integer aa, vv;
        begin
            aa = a; vv = v;
            if (noise_amp > 0) begin
                if (aa == BASE) aa = BASE + $urandom_range(2 * noise_amp, 0) - noise_amp;
                if (vv == BASE) vv = BASE + $urandom_range(2 * noise_amp, 0) - noise_amp;
            end
            @(negedge clk); a_s = aa; v_s = vv; en = 1;
            @(negedge clk); en = 0;
            tick_no = tick_no + 1;
            model_ctrl;                   // controller sees the spikes from the previous tick
            model_lif(0, aa);
            model_lif(1, vv);
            check_tick;
            repeat (TICK_CLKS - 2) @(negedge clk);
        end
    endtask

    task idle(input integer n);
        integer i;
        begin for (i = 0; i < n; i = i + 1) tick(BASE, BASE); end
    endtask

    // nbeats beats of the given period; QRS pr ticks after the P wave (if qrs=1)
    task sinus(input integer nbeats, input integer period, input integer pr, input integer qrs);
        integer b, t;
        begin
            for (b = 0; b < nbeats; b = b + 1)
                for (t = 0; t < period; t = t + 1)
                    tick((t == 0) ? 4095 : BASE, (qrs != 0 && t == pr) ? 4095 : BASE);
        end
    endtask

    task start_test(input string name);
        begin
            reset_dut;
            $display("--- %s", name);
        end
    endtask

    task end_test(input string name);
        begin
            $display("    %s: AS=%0d AP=%0d VS=%0d VP=%0d", name, cnt_as, cnt_ap, cnt_vs, cnt_vp);
            tot_as = tot_as + cnt_as; tot_ap = tot_ap + cnt_ap;
            tot_vs = tot_vs + cnt_vs; tot_vp = tot_vp + cnt_vp;
        end
    endtask

    task expect_eq(input string id, input integer got, input integer exp);
        begin
            if (got !== exp) err(id, $sformatf("got %0d, expected %0d", got, exp));
        end
    endtask

    // ---- directed tests ------------------------------------------------------
    task run_directed;
        begin
            // D1: healthy sinus rhythm, pacing must stay inhibited
            start_test("D1 normal sinus rhythm");
            sinus(10, 800, 120, 1);
            expect_eq("D1_AS", cnt_as, 10); expect_eq("D1_VS", cnt_vs, 10);
            expect_eq("D1_AP", cnt_ap, 0);  expect_eq("D1_VP", cnt_vp, 0);
            end_test("D1");

            // D2: sinus arrest, pacing takes over at exactly the lower rate
            start_test("D2 sinus arrest");
            sinus(3, 800, 120, 1);
            idle(4000);
            expect_eq("D2_AS", cnt_as, 3); expect_eq("D2_VS", cnt_vs, 3);
            if (cnt_ap < 3 || cnt_vp < 3) err("D2_PACED", "pacing did not take over after the arrest");
            end_test("D2");

            // D3: AV block, every P wave must be followed by a ventricular pace
            start_test("D3 AV block");
            sinus(8, 800, 0, 0);
            idle(200);
            expect_eq("D3_AS", cnt_as, 8); expect_eq("D3_VP", cnt_vp, 8);
            expect_eq("D3_VS", cnt_vs, 0); expect_eq("D3_AP", cnt_ap, 0);
            end_test("D3");

            // D4: noise below the dead zone must not be sensed
            start_test("D4 noise rejection");
            noise_amp = 90;
            idle(3000);
            expect_eq("D4_AS", cnt_as, 0); expect_eq("D4_VS", cnt_vs, 0);
            if (cnt_vp < 2) err("D4_PACED", "expected paced rhythm under noise");
            sinus(6, 800, 120, 1);
            noise_amp = 0;
            end_test("D4");

            // D5: events inside PVARP and VRP are ignored, a later P wave is sensed
            start_test("D5 refractory periods");
            begin : d5
                integer t;
                for (t = 0; t < 700; t = t + 1)
                    tick((t == 0 || t == 220 || t == 430) ? 4095 : BASE,
                         (t == 120 || t == 230) ? 4095 : BASE);
            end
            expect_eq("D5_AS", cnt_as, 2); expect_eq("D5_VS", cnt_vs, 1);
            expect_eq("D5_VP", cnt_vp, 1); expect_eq("D5_AP", cnt_ap, 0);
            end_test("D5");

            // D6: a ventricular-channel spike right after an atrial pace is crosstalk
            // and must be blanked (no VS)
            start_test("D6 crosstalk blanking");
            begin : d6
                integer i, x;
                x = -1;
                for (i = 0; i < 1000; i = i + 1) begin
                    if (m_ap) x = 5;
                    tick(BASE, (x == 0) ? 4095 : BASE);
                    if (x >= 0) x = x - 1;
                end
            end
            expect_eq("D6_AP", cnt_ap, 1); expect_eq("D6_VS", cnt_vs, 0);
            end_test("D6");
        end
    endtask

    // ---- random test ---------------------------------------------------------
    task run_random(input integer nticks);
        integer i, p_cnt, q_cnt, x_cnt, a, v;
        begin
            start_test("R1 constrained random");
            p_cnt = 0; q_cnt = -1; x_cnt = -1;
            for (i = 0; i < nticks; i = i + 1) begin
                a = BASE; v = BASE;
                if (i % 4000 == 0) noise_amp = $urandom_range(95, 0);
                if (p_cnt == 0) begin
                    if ($urandom_range(99, 0) < 85) a = 4095;                  // P present
                    if ($urandom_range(99, 0) < 80) q_cnt = $urandom_range(220, 40); // QRS follows
                    p_cnt = $urandom_range(1400, 350);
                end
                p_cnt = p_cnt - 1;
                if (q_cnt == 0) v = 4095;
                if (q_cnt >= 0) q_cnt = q_cnt - 1;
                if ($urandom_range(999, 0) < 3) v = 4095;                      // stray QRS
                if (m_ap && $urandom_range(1, 0) == 1) x_cnt = $urandom_range(14, 1); // crosstalk
                if (x_cnt == 0) v = 4095;
                if (x_cnt >= 0) x_cnt = x_cnt - 1;
                tick(a, v);
            end
            end_test("R1");
        end
    endtask

    // ---- main ----------------------------------------------------------------
    reg [8*16-1:0] sel;
    initial begin
        if (!$value$plusargs("TEST=%s", sel)) sel = "all";
        $display("=== tb_pacemaker (TEST=%0s) ===", sel);
        if (sel == "all" || sel == "directed") run_directed;
        if (sel == "all" || sel == "random")   run_random(60000);
        if (sel == "all" || sel == "random") begin
            $display("coverage: AS=%0d AP=%0d VS=%0d VP=%0d blocked_A=%0d blocked_V=%0d",
                     tot_as, tot_ap, tot_vs, tot_vp, blk_a, blk_v);
            if (tot_as == 0 || tot_ap == 0 || tot_vs == 0 || tot_vp == 0 || blk_a == 0 || blk_v == 0)
                err("COVERAGE", "a pacing event type or a blocking case was never exercised");
        end
        $display("--------------------------------------------");
        $display(" %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display(" TEST PASSED"); else $display(" TEST FAILED");
        $display("--------------------------------------------");
        $finish;
    end
endmodule
