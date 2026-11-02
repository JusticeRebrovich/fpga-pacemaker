//==============================================================
// pacemaker.v
// Nexys A7-100T  |  Verilog  |  100 MHz system clock
//
// Function:
//   Generates a pacemaker heartbeat (~70 BPM).
//   - pace_out  : short pulse every ~0.85 s  → PACE_LED1 on PCB
//   - alarm_out : mirrors button_in (hold button = alarm active)
//   - LED[0]    : onboard mirror of pace_out  (debug without PCB)
//   - LED[15]   : onboard mirror of alarm_out
//
// PMOD JA wiring:
//   pace_out  → JA pin 2 (J1)  → 470Ω → PACE_LED1
//   alarm_out → JA pin 4 (L2)  → 470Ω → ALARM_LED1
//   button_in ← JA pin 6 (J2)  ← SW_Push (10k pulldown on PCB)
//   GND       → JA pin 5 or 11 → PCB GND
//   VCC 3.3V  → JA pin 6 or 12 → PCB VCC_3V3
//==============================================================

module pacemaker (
    input  wire        clk,        // 100 MHz  — W5
    input  wire        rst,        // btnC center button (active HIGH) — N17
    input  wire        button_in,  // PCB SW_Push via PMOD JA pin 6 — J2
    output reg         pace_out,   // PMOD JA pin 2 (J1) → PACE_LED1
    output reg         alarm_out,  // PMOD JA pin 4 (L2) → ALARM_LED1
    output reg  [15:0] LED         // onboard LD0–LD15
);

    //----------------------------------------------------------
    // Parameters — all cycle counts at 100 MHz
    //   BEAT_PERIOD : full heartbeat period  (~70 BPM = 0.857 s)
    //   PULSE_WIDTH : how long LED stays ON  (~100 ms)
    //----------------------------------------------------------
    parameter BEAT_PERIOD = 27'd85_000_000;   // 0.85 s
    parameter PULSE_WIDTH = 27'd10_000_000;   // 0.10 s

    reg [26:0] counter;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter   <= 27'd0;
            pace_out  <= 1'b0;
            alarm_out <= 1'b0;
            LED       <= 16'b0;
        end else begin

            // ── Heartbeat counter ──────────────────────────
            if (counter >= BEAT_PERIOD - 1'b1)
                counter <= 27'd0;
            else
                counter <= counter + 1'b1;

            // ── Pace pulse (on for first PULSE_WIDTH counts)
            if (counter < PULSE_WIDTH) begin
                pace_out <= 1'b1;
                LED[0]   <= 1'b1;
            end else begin
                pace_out <= 1'b0;
                LED[0]   <= 1'b0;
            end

            // ── Alarm (button held = bradycardia alert) ────
            alarm_out <= button_in;
            LED[15]   <= button_in;

            // ── Unused LEDs off ────────────────────────────
            LED[14:1] <= 14'b0;

        end
    end

endmodule
