`timescale 1ns/1ps
module ecg_rom #( //electrocardiogram (electrical signal of heart)
parameter SAMPLE_COUNT = 10 //generates fake waveform
)(
    input wire clk,
    input wire rst,
    input wire [3:0] addr,
    output reg [11:0] data
);
always @(posedge clk) begin
    if (rst)
    data <= 12'd0;
    else begin
    case (addr)
        //first couple of beats
        4'd0: data <= 12'd4095; //4095 spike is normal heartbeat value(highest 12bit value)
        4'd1: data <= 12'd2048; //2048 is flatline, too many pacemaker will fire
        4'd2: data <= 12'd2048;
        4'd3: data <= 12'd2048;
        4'd4: data <= 12'd2048;
        4'd5: data <= 12'd2048;
        4'd6: data <= 12'd4095; //beats resume
        4'd7: data <= 12'd4095;
        4'd8: data <= 12'd4095;
        4'd9: data <= 12'd4095;
        default: data <= 12'd2048;
endcase
end
end
endmodule
    module adaptive_lif #( //leaky-integrate-fire (neuron model to detect spikes)
        parameter SAMPLE_WIDTH = 12,
        parameter ACC_WIDTH = 20,
        parameter THETA_WIDTH = 16
)(
        input wire clk,
        input wire rst,
        input wire sample_clk_en,
        input wire signed [SAMPLE_WIDTH-1:0] sample_in,
        output reg spike_out,                          //1 tick pulse when beat detected
        output reg signed [ACC_WIDTH-1:0] v_out,
        output reg signed [THETA_WIDTH-1:0] theta_out //threshold
        );
        //Parameters
        localparam integer GAIN = 40; //sensitivity
        localparam integer DEAD_ZONE = 100; //noise threshold
        localparam integer V_RESET = 0;
        localparam integer THETA_BASE = 16'd1536;
        localparam integer THETA_INC = 16'd128; // increase threshold after spike(momentarily to prevent refire)
        localparam integer TAU_TH_DEC_SHIFT = 5;// decay to base rate
        localparam integer REFRACT_TICKS =3; // time it ingnores new inputs

        reg signed [ACC_WIDTH-1:0] v;
        reg signed [THETA_WIDTH-1:0] theta;
        reg [7:0] refract_cnt;
        integer signed_sample;
        integer drive;
always @(posedge clk) begin // spike or QRS detector functions
    if (rst) begin
    v <= 0;
    theta <= THETA_BASE;
    spike_out <= 0;
    refract_cnt <= 0;
    end else begin
        spike_out <= 0;
        if (sample_clk_en) begin
        if (refract_cnt > 0)
            refract_cnt <= refract_cnt -1;
        else begin
        signed_sample = sample_in - 12'sd2048;
        if ((signed_sample > DEAD_ZONE) || (signed_sample < -DEAD_ZONE))
            drive = signed_sample * GAIN;
        else
            drive = 0;
        v <= v + drive - (v >>> 4);
        if (v >= theta) begin
        spike_out <= 1;
        v <= V_RESET;
        theta <= theta + THETA_INC;
        refract_cnt <= REFRACT_TICKS;
        end else begin
            theta <= theta - ((theta - THETA_BASE) >>> TAU_TH_DEC_SHIFT);
        end
     end
  end
  v_out <= v;
  theta_out <= theta;
  end
  end
  endmodule
module pacemaker_ctrl #(
    parameter integer SAMPLE_FREQ = 1000,
    parameter integer LOWER_RATE_BPM = 60,
    parameter integer BLANKING_MS = 40,
    parameter integer REFRACT_MS = 200
)(
    input wire clk,
    input wire rst,
    input wire sample_clk_en,
    input wire detector_spike,
    output reg pace_pulse
);
    localparam integer ESCAPE_INTERVAL_TICKS = (60 * SAMPLE_FREQ) / LOWER_RATE_BPM;
    localparam integer BLANK_TICKS = (BLANKING_MS * SAMPLE_FREQ) / 1000;
    localparam integer REFRACT_TICKS = (REFRACT_MS * SAMPLE_FREQ) / 1000;

        integer timer_since_event;
        integer blank_until;
        integer refract_until;
        integer tick;

always @(posedge clk) begin
    if (rst) begin
    timer_since_event <= ESCAPE_INTERVAL_TICKS;
    blank_until <= 0;
    refract_until <= 0;
    tick <= 0;
    pace_pulse <= 0;
end else begin
    pace_pulse <= 0;
    if (sample_clk_en) begin
    tick <= tick + 1;
    if (detector_spike && tick >= blank_until && tick >= refract_until) begin
        timer_since_event <= 0;
        refract_until <= tick + REFRACT_TICKS;
    end else begin
        timer_since_event <= timer_since_event + 1;
    end
        if (timer_since_event >= ESCAPE_INTERVAL_TICKS) begin
            pace_pulse <= 1;
            timer_since_event <= 0;
            blank_until <= tick + BLANK_TICKS;
end
end
end
end
endmodule

module top (
    input wire CLK,
    input wire RSTn,
    output wire LED_HEART,// natural beat
    output wire LED_PACE // pace pulse
);
    parameter integer BOARD_CLK_HZ = 100_000_000; // reduce speed of fpga clk
    parameter integer SAMPLE_RATE = 1000;
    parameter integer SAMPLE_COUNT = 10;
    localparam integer DIV = BOARD_CLK_HZ / SAMPLE_RATE;

    reg[31:0] divcnt = 0;
    reg sample_clk_en = 0;

    always @(posedge CLK) begin
        if (!RSTn) begin
        divcnt <= 0;
        sample_clk_en <= 0;
    end else begin
        if (divcnt >= DIV -1) begin
        divcnt <= 0;
        sample_clk_en <= 1;
    end else begin
        divcnt <= divcnt +1;
        sample_clk_en <= 0;
end
end
end

        reg [3:0] sample_addr = 0;
        always @(posedge CLK) begin
            if (!RSTn)
                sample_addr <= 0;
            else if (sample_clk_en)
                sample_addr <= (sample_addr == SAMPLE_COUNT-1) ? 0 : sample_addr +1;
end
    wire [11:0] ecg_sample;
    ecg_rom rom_inst (
    .clk(CLK) ,
    .rst(~RSTn) ,
    .addr(sample_addr) ,
    .data(ecg_sample)
);
    wire spike;
    wire signed [19:0] v_out;
    wire signed [15:0] theta_out;

    adaptive_lif lif_inst (
    .clk(CLK) ,
    .rst(~RSTn) ,
    .sample_clk_en(sample_clk_en) ,
    .sample_in(ecg_sample) ,
    .spike_out(spike) ,
    .v_out(v_out) ,
    .theta_out(theta_out)
);

wire pace;
    pacemaker_ctrl pm_inst (
        .clk(CLK) ,
        .rst(~RSTn) ,
        .sample_clk_en(sample_clk_en) ,
        .detector_spike(spike) ,
        .pace_pulse(pace)
);
    assign LED_HEART = spike;
    assign LED_PACE = pace;
endmodule
