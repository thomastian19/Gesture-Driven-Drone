`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/23/2026 09:53:47 PM
// Design Name: 
// Module Name: sbus_top
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


module sbus_top(
	input rx,
	input clk,
	output sbus_out
	);

    wire one;
    wire [7:0] two;

	uart_rx instance1(.rx(rx), .clk(clk), .valid(one), .data_out(two));
	parser instance2(.sbus_out(sbus_out), .clk(clk), .valid(one), .data_byte(two));
endmodule
