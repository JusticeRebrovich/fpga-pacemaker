`timescale 1ns/1ps
//==============================================================================
// tb_top_demo.sv : checks the board-level design (ECG generator, LED stretching,
// scenario switches) the way it behaves on the Nexys A7.
//
// The board clock is slowed to 40 kHz so a 1 ms sample tick takes 40 clocks
// instead of 100000. The design is otherwise unchanged.
//
// Run in Vivado with rtl/pacemaker.v and this file, simulation top tb_top_demo.
//==============================================================================
module tb_top_demo;
    reg        CLK  = 1'b0;
    reg        RSTn = 1'b0;
    reg  [1:0] SW   = 2'b00;
    wire       LED_A_SENSE, LED_V_SENSE, LED_A_PACE, LED_V_PACE;

    pacemaker_top #(.BOARD_CLK_HZ(40_000)) dut (
        .CLK(CLK), .RSTn(RSTn), .SW(SW),
        .LED_A_SENSE(LED_A_SENSE), .LED_V_SENSE(LED_V_SENSE),
        .LED_A_PACE(LED_A_PACE),   .LED_V_PACE(LED_V_PACE)
    );
    always #5 CLK = ~CLK;

    integer n_as = 0, n_vs = 0, n_ap = 0, n_vp = 0, errors = 0;
    always @(posedge LED_A_SENSE) n_as = n_as + 1;
    always @(posedge LED_V_SENSE) n_vs = n_vs + 1;
    always @(posedge LED_A_PACE)  n_ap = n_ap + 1;
    always @(posedge LED_V_PACE)  n_vp = n_vp + 1;

    // one simulated millisecond = 40 clocks of 10 ns
    task run_ms(input integer ms);
        begin repeat (ms * 40) @(posedge CLK); end
    endtask

    task scenario(input [1:0] mode, input integer ms, input string name);
        begin
            RSTn = 0; SW = mode; repeat (4) @(posedge CLK);
            n_as = 0; n_vs = 0; n_ap = 0; n_vp = 0;
            RSTn = 1;
            run_ms(ms);
            $display("%-22s AS=%0d VS=%0d AP=%0d VP=%0d", name, n_as, n_vs, n_ap, n_vp);
        end
    endtask

    task check(input string id, input bit ok);
        begin
            if (!ok) begin errors = errors + 1; $display("ERROR [%s]", id); end
        end
    endtask

    initial begin
        // mode 0: 75 BPM sinus rhythm for 8 s, pacing inhibited
        scenario(2'd0, 8000, "normal sinus");
        check("N_SENSE", n_as >= 9 && n_vs >= 9);
        check("N_NOPACE", n_ap == 0 && n_vp == 0);

        // mode 1: beats stop for 7 of every 12 beats, pacing takes over
        scenario(2'd1, 13000, "sinus arrest");
        check("A_SENSE", n_as >= 5 && n_vs >= 5);
        check("A_PACED", n_ap >= 3 && n_vp >= 3);

        // mode 2: P waves with no QRS, every P wave gets a ventricular pace
        scenario(2'd2, 8000, "AV block");
        check("B_AS", n_as >= 9);
        check("B_VP", n_vp >= 9 && n_vs == 0);
        check("B_NOAP", n_ap == 0);

        // mode 3: noise inside the dead zone must not change the behavior
        scenario(2'd3, 8000, "noisy sinus");
        check("Z_SENSE", n_as >= 9 && n_vs >= 9);
        check("Z_NOPACE", n_ap == 0 && n_vp == 0);

        $display("--------------------------------------------");
        if (errors == 0) $display(" TEST PASSED"); else $display(" TEST FAILED (%0d errors)", errors);
        $display("--------------------------------------------");
        $finish;
    end
endmodule
