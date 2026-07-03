`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/06/2026 07:26:48 PM
// Design Name: 
// Module Name: uart_rx_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module uart_rx_tb;


    reg        clk;
    reg        rx;
    wire       valid;
    wire [7:0] data_out;

    localparam BIT_PERIOD = 8680;


    uart_rx dut (
        .clk     (clk),
        .rx      (rx),
        .valid   (valid),
        .data_out(data_out)
    );


    initial clk = 0;
    always #42 clk = ~clk;

    task send_byte(input [7:0] b);
        integer i;
        begin

            rx = 1'b0;
            #(BIT_PERIOD);


            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i];
                #(BIT_PERIOD);
            end


            rx = 1'b1;
            #(BIT_PERIOD);
        end
    endtask


    initial begin

        rx = 1'b1;


        #(BIT_PERIOD * 2);


        send_byte(8'h55);


        #(BIT_PERIOD * 2);


        send_byte(8'hA3);


        #(BIT_PERIOD * 4);

        $display("Simulation complete");
        $finish;
    end


    always @(posedge clk) begin
        if (valid)
            $display("Time=%0t  RECEIVED byte = 0x%02h", $time, data_out);
    end

endmodule
