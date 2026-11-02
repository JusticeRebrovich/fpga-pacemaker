`timescale 1ns/1ps
//==============================================================================
// pacemaker.v : dual-chamber (DDD-style) digital pacemaker, Nexys A7-100T
//
//   ecg_gen --+--> adaptive_lif (atrial)    --+
//             |                               +--> pacemaker_ctrl --> AS/AP/VS/VP
//             +--> adaptive_lif (ventricular) -+
//
// Everything runs from the 100 MHz board clock. A clock divider produces a
// one-clock sample enable (1 kHz by default, so one "tick" = 1 ms). All state
// updates only on sample ticks, and every output is held for a whole tick.
//
// Timing parameters of the controller are in ticks:
//   LRI_TICKS    lower rate interval (1000 = 60 BPM)
//   AV_TICKS     AV delay: atrial event -> ventricular pace
//   PVARP_TICKS  atrial sensing ignored after a ventricular event
//   VRP_TICKS    ventricular sensing ignored after a ventricular event
//   ABLANK_TICKS atrial channel blanked after an atrial pace
//   XBLANK_TICKS ventricular channel blanked after an atrial pace (crosstalk)
//
// Fault-injection defines used by sim/regress.py (never defined for hardware):
//   FI_AV, FI_PVARP, FI_AP_EARLY, FI_NODZ, FI_XBLANK
//==============================================================================


//------------------------------------------------------------------------------
// Adaptive LIF beat detector (one per chamber).
//   v     : membrane voltage, integrates the baseline-subtracted sample
//   theta : firing threshold, jumps after a spike and decays back to THETA_BASE
// Samples inside +/-DEAD_ZONE of the baseline are treated as noise (no drive).
//------------------------------------------------------------------------------
module adaptive_lif #(
    parameter integer SAMPLE_WIDTH  = 12,
    parameter integer ACC_WIDTH     = 20,
    parameter integer THETA_WIDTH   = 16,
    parameter integer GAIN          = 40,
    parameter integer DEAD_ZONE     = 100,
    parameter integer LEAK_SHIFT    = 4,     // leak = v / 16 per tick
    parameter integer THETA_BASE    = 1536,
    parameter integer THETA_INC     = 128,   // threshold rise after a spike
    parameter integer THETA_MAX     = 8192,
    parameter integer TAU_SHIFT     = 5,     // threshold decays by excess / 32 per tick
    parameter integer REFRACT_TICKS = 3
)(
    input  wire                           clk,
    input  wire                           rst,
    input  wire                           sample_clk_en,
    input  wire [SAMPLE_WIDTH-1:0]        sample_in,   // unsigned, midscale = baseline
    output reg                            spike_out,   // beat detected, held one tick
    output reg signed [ACC_WIDTH-1:0]     v_out,
    output reg signed [THETA_WIDTH-1:0]   theta_out
);
    localparam integer BASELINE = 1 << (SAMPLE_WIDTH - 1);
    localparam integer ACC_MAX  =  (1 << (ACC_WIDTH - 1)) - 1;
    localparam integer ACC_MIN  = -(1 << (ACC_WIDTH - 1));

    reg [7:0] refract_cnt;
    integer   centered, drive, v_next;

    always @(posedge clk) begin
        if (rst) begin
            v_out       <= 0;
            theta_out   <= THETA_BASE;
            spike_out   <= 1'b0;
            refract_cnt <= 8'd0;
        end else if (sample_clk_en) begin
            spike_out <= 1'b0;
            if (refract_cnt != 0) begin
                refract_cnt <= refract_cnt - 1'b1;
            end else begin
                centered = $signed({1'b0, sample_in}) - BASELINE;
`ifdef FI_NODZ
                if (centered != 0)
`else
                if (centered > DEAD_ZONE || centered < -DEAD_ZONE)
`endif
                    drive = centered * GAIN;
                else
                    drive = 0;

                v_next = v_out + drive - (v_out >>> LEAK_SHIFT);
                if (v_next > ACC_MAX) v_next = ACC_MAX;      // saturate, never wrap
                else if (v_next < ACC_MIN) v_next = ACC_MIN;

                if (v_next >= theta_out) begin
                    spike_out   <= 1'b1;
                    v_out       <= 0;
                    refract_cnt <= REFRACT_TICKS;
                    theta_out   <= (theta_out + THETA_INC > THETA_MAX) ? THETA_MAX
                                                                       : theta_out + THETA_INC;
                end else begin
                    v_out     <= v_next;
                    theta_out <= theta_out - ((theta_out - THETA_BASE) >>> TAU_SHIFT);
                end
            end
        end
    end
endmodule


//------------------------------------------------------------------------------
// Dual-chamber pacing controller.
//
//   V event (VS or VP): restarts the lower-rate timer, opens atrial wait, starts
//                       VRP and PVARP.
//   Atrial wait:        AS if an atrial spike arrives outside PVARP/blanking;
//                       otherwise AP when LRI - AV ticks have passed since the
//                       last V event.
//   After an atrial event: if no VS within AV ticks, VP.
// Result: the ventricle is never paced slower than the lower rate, and pacing
// is inhibited whenever the heart conducts on its own.
//------------------------------------------------------------------------------
module pacemaker_ctrl #(
    parameter integer LRI_TICKS    = 1000,
    parameter integer AV_TICKS     = 150,
    parameter integer PVARP_TICKS  = 250,
    parameter integer VRP_TICKS    = 200,
    parameter integer ABLANK_TICKS = 40,
    parameter integer XBLANK_TICKS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire sample_clk_en,
    input  wire a_spike,        // atrial detector output
    input  wire v_spike,        // ventricular detector output
    output reg  a_sense,        // accepted atrial sense   (AS)
    output reg  a_pace,         // atrial pace            (AP)
    output reg  v_sense,        // accepted ventricular sense (VS)
    output reg  v_pace          // ventricular pace       (VP)
);
    localparam integer VA_TICKS = LRI_TICKS - AV_TICKS;   // V event -> AP
    localparam integer T_MAX    = 65535;

    integer since_v, since_a;                 // ticks since last V / atrial event
    integer vrp_cnt, pvarp_cnt, ablank_cnt, xblank_cnt;
    reg     a_wait;                           // waiting for an atrial event
    reg     av_active;                        // AV delay running
    integer va_n, av_n;
    reg     vs_ok, as_ok, ap_due, vp_due;

    always @(posedge clk) begin
        if (rst) begin
            since_v    <= 0;
            since_a    <= 0;
            vrp_cnt    <= 0;
            pvarp_cnt  <= 0;
            ablank_cnt <= 0;
            xblank_cnt <= 0;
            a_wait     <= 1'b1;
            av_active  <= 1'b0;
            a_sense    <= 1'b0;
            a_pace     <= 1'b0;
            v_sense    <= 1'b0;
            v_pace     <= 1'b0;
        end else if (sample_clk_en) begin
            a_sense <= 1'b0;
            a_pace  <= 1'b0;
            v_sense <= 1'b0;
            v_pace  <= 1'b0;

            va_n = (since_v >= T_MAX) ? T_MAX : since_v + 1;
            av_n = (since_a >= T_MAX) ? T_MAX : since_a + 1;

            vs_ok  = v_spike && (vrp_cnt == 0) && (xblank_cnt == 0);
`ifdef FI_XBLANK
            vs_ok  = v_spike && (vrp_cnt == 0);
`endif
            as_ok  = a_spike && a_wait && (pvarp_cnt == 0) && (ablank_cnt == 0);
`ifdef FI_PVARP
            as_ok  = a_spike && a_wait && (ablank_cnt == 0);
`endif
`ifdef FI_AP_EARLY
            ap_due = a_wait && (va_n >= VA_TICKS - 10);
`else
            ap_due = a_wait && (va_n >= VA_TICKS);
`endif
`ifdef FI_AV
            vp_due = av_active && (av_n >= AV_TICKS + 1);
`else
            vp_due = av_active && (av_n >= AV_TICKS);
`endif

            since_v <= va_n;
            since_a <= av_n;
            if (vrp_cnt    > 0) vrp_cnt    <= vrp_cnt    - 1;
            if (pvarp_cnt  > 0) pvarp_cnt  <= pvarp_cnt  - 1;
            if (ablank_cnt > 0) ablank_cnt <= ablank_cnt - 1;
            if (xblank_cnt > 0) xblank_cnt <= xblank_cnt - 1;

            if (vs_ok || vp_due) begin                    // ventricular event
                v_sense   <= vs_ok;
                v_pace    <= !vs_ok;
                since_v   <= 0;
                a_wait    <= 1'b1;
                av_active <= 1'b0;
                vrp_cnt   <= VRP_TICKS;
                pvarp_cnt <= PVARP_TICKS;
            end else if (as_ok || ap_due) begin           // atrial event
                a_sense   <= as_ok;
                a_pace    <= !as_ok;
                a_wait    <= 1'b0;
                av_active <= 1'b1;
                since_a   <= 0;
                if (!as_ok) begin
                    ablank_cnt <= ABLANK_TICKS;
                    xblank_cnt <= XBLANK_TICKS;
                end
            end
        end
    end
endmodule


//------------------------------------------------------------------------------
// Sensing + pacing core: two detectors feeding the controller. This is the
// module the self-checking testbench drives directly.
//------------------------------------------------------------------------------
module pacemaker_core #(
    parameter integer LRI_TICKS    = 1000,
    parameter integer AV_TICKS     = 150,
    parameter integer PVARP_TICKS  = 250,
    parameter integer VRP_TICKS    = 200,
    parameter integer ABLANK_TICKS = 40,
    parameter integer XBLANK_TICKS = 20
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_clk_en,
    input  wire [11:0] a_sample,
    input  wire [11:0] v_sample,
    output wire        a_sense,
    output wire        a_pace,
    output wire        v_sense,
    output wire        v_pace,
    output wire        a_spike,      // raw detector outputs, for debug and checking
    output wire        v_spike
);
    wire signed [19:0] a_v, v_v;
    wire signed [15:0] a_theta, v_theta;

    adaptive_lif a_lif (
        .clk(clk), .rst(rst), .sample_clk_en(sample_clk_en), .sample_in(a_sample),
        .spike_out(a_spike), .v_out(a_v), .theta_out(a_theta)
    );
    adaptive_lif v_lif (
        .clk(clk), .rst(rst), .sample_clk_en(sample_clk_en), .sample_in(v_sample),
        .spike_out(v_spike), .v_out(v_v), .theta_out(v_theta)
    );
    pacemaker_ctrl #(
        .LRI_TICKS(LRI_TICKS), .AV_TICKS(AV_TICKS), .PVARP_TICKS(PVARP_TICKS),
        .VRP_TICKS(VRP_TICKS), .ABLANK_TICKS(ABLANK_TICKS), .XBLANK_TICKS(XBLANK_TICKS)
    ) ctrl (
        .clk(clk), .rst(rst), .sample_clk_en(sample_clk_en),
        .a_spike(a_spike), .v_spike(v_spike),
        .a_sense(a_sense), .a_pace(a_pace), .v_sense(v_sense), .v_pace(v_pace)
    );
endmodule


//------------------------------------------------------------------------------
// Synthetic two-channel ECG for the board demo. Samples are midscale (2048)
// with 4095 spikes for a P wave (atrial) and a QRS (ventricular).
//   mode 0: normal sinus rhythm
//   mode 1: sinus arrest, beats stop for part of every cycle (pacing takes over)
//   mode 2: AV block, P waves with no QRS (VP follows every AS)
//   mode 3: normal rhythm plus noise inside the detector dead zone
//------------------------------------------------------------------------------
module ecg_gen #(
    parameter integer PERIOD       = 800,    // ticks per intrinsic beat (75 BPM)
    parameter integer PR           = 120,    // P to QRS delay, shorter than AV_TICKS
    parameter integer ARREST_ON    = 5,      // mode 1: beats present per cycle
    parameter integer ARREST_CYCLE = 12      // mode 1: beats per cycle
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_clk_en,
    input  wire [1:0]  mode,
    output wire [11:0] a_sample,
    output wire [11:0] v_sample
);
    reg [15:0] phase;
    reg [7:0]  beat;
    reg [7:0]  lfsr;

    always @(posedge clk) begin
        if (rst) begin
            phase <= 16'd0;
            beat  <= 8'd0;
            lfsr  <= 8'hA5;
        end else if (sample_clk_en) begin
            lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
            if (phase == PERIOD - 1) begin
                phase <= 16'd0;
                beat  <= (beat == ARREST_CYCLE - 1) ? 8'd0 : beat + 1'b1;
            end else begin
                phase <= phase + 1'b1;
            end
        end
    end

    wire beat_on = (mode == 2'd1) ? (beat < ARREST_ON) : 1'b1;
    wire a_hit   = beat_on && (phase == 0);
    wire v_hit   = beat_on && (mode != 2'd2) && (phase == PR);
    // noise stays within +/-64 counts, inside the detector dead zone
    wire [11:0] noise_a = (mode == 2'd3) ? (12'd2048 + {5'd0, lfsr[6:0]} - 12'd64) : 12'd2048;
    wire [11:0] noise_v = (mode == 2'd3) ? (12'd2048 + {5'd0, lfsr[3:0], lfsr[7:5]} - 12'd64) : 12'd2048;

    assign a_sample = a_hit ? 12'd4095 : noise_a;
    assign v_sample = v_hit ? 12'd4095 : noise_v;
endmodule


//------------------------------------------------------------------------------
// Board top level for the Nexys A7-100T.
//   SW[1:0]  scenario select (see ecg_gen)
//   LD0 atrial sense, LD1 ventricular sense, LD2 atrial pace, LD3 ventricular pace
// Events last one 1 ms tick, so each LED is stretched to LED_HOLD_TICKS to be visible.
//------------------------------------------------------------------------------
module pacemaker_top #(
    parameter integer BOARD_CLK_HZ   = 100_000_000,
    parameter integer SAMPLE_RATE    = 1000,
    parameter integer LED_HOLD_TICKS = 100
)(
    input  wire       CLK,
    input  wire       RSTn,
    input  wire [1:0] SW,
    output wire       LED_A_SENSE,
    output wire       LED_V_SENSE,
    output wire       LED_A_PACE,
    output wire       LED_V_PACE
);
    localparam integer DIV = BOARD_CLK_HZ / SAMPLE_RATE;

    wire rst = ~RSTn;

    reg [31:0] divcnt        = 32'd0;
    reg        sample_clk_en = 1'b0;
    always @(posedge CLK) begin
        if (rst) begin
            divcnt        <= 32'd0;
            sample_clk_en <= 1'b0;
        end else if (divcnt >= DIV - 1) begin
            divcnt        <= 32'd0;
            sample_clk_en <= 1'b1;
        end else begin
            divcnt        <= divcnt + 1'b1;
            sample_clk_en <= 1'b0;
        end
    end

    wire [11:0] a_sample, v_sample;
    wire        a_sense, a_pace, v_sense, v_pace, a_spike, v_spike;

    ecg_gen gen (
        .clk(CLK), .rst(rst), .sample_clk_en(sample_clk_en), .mode(SW),
        .a_sample(a_sample), .v_sample(v_sample)
    );
    pacemaker_core core (
        .clk(CLK), .rst(rst), .sample_clk_en(sample_clk_en),
        .a_sample(a_sample), .v_sample(v_sample),
        .a_sense(a_sense), .a_pace(a_pace), .v_sense(v_sense), .v_pace(v_pace),
        .a_spike(a_spike), .v_spike(v_spike)
    );

    reg [8:0] hold_as, hold_vs, hold_ap, hold_vp;
    always @(posedge CLK) begin
        if (rst) begin
            hold_as <= 9'd0; hold_vs <= 9'd0; hold_ap <= 9'd0; hold_vp <= 9'd0;
        end else if (sample_clk_en) begin
            hold_as <= a_sense ? LED_HOLD_TICKS : (hold_as != 0 ? hold_as - 1'b1 : 9'd0);
            hold_vs <= v_sense ? LED_HOLD_TICKS : (hold_vs != 0 ? hold_vs - 1'b1 : 9'd0);
            hold_ap <= a_pace  ? LED_HOLD_TICKS : (hold_ap != 0 ? hold_ap - 1'b1 : 9'd0);
            hold_vp <= v_pace  ? LED_HOLD_TICKS : (hold_vp != 0 ? hold_vp - 1'b1 : 9'd0);
        end
    end

    assign LED_A_SENSE = (hold_as != 0);
    assign LED_V_SENSE = (hold_vs != 0);
    assign LED_A_PACE  = (hold_ap != 0);
    assign LED_V_PACE  = (hold_vp != 0);
endmodule
