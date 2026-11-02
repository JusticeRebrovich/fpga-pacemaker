`timescale 1ns / 1ps
    module testbench;

        reg CLK;
        reg RSTn;
        wire LED_HEART;
        wire LED_PACE;

    initial CLK=0;
    always #5 CLK = ~CLK; //clk generator
        initial begin
        RSTn = 0; // reset generator
        #100;
        RSTn =1;
    end
top dut ( //top module as device under test
    .CLK(CLK) ,
    .RSTn(RSTn) ,
    .LED_HEART(LED_HEART) ,
    .LED_PACE(LED_PACE)
);
    initial begin
        $display("Time(ns) LED_HEART LED_PACE"); //graph label
        $monitor("%0t %b %b", $time, LED_HEART, LED_PACE); //shows data under header label
        #(200_000_000); //200ms
        $finish;
end
endmodule
