`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/18/2026 05:47:41 PM
// Design Name: 
// Module Name: parser
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


module parser(
	input [7:0]data_byte,
	input valid,
	input clk,
	output sbus_out);

localparam WAIT = 1'b0;
localparam READ = 1'b1;
localparam IDLE = 3'b000;
localparam SEND_START_BIT = 3'b001;
localparam SEND_DATA_BIT = 3'b010;
localparam SEND_PARITY_BIT = 3'b011;
localparam SEND_STOP_BIT = 3'b100;
localparam LOAD = 2'b00;
localparam SEND = 2'b01;
localparam WAIT_BYTE = 2'b10;
localparam GAP = 2'b11;
localparam SAFE_NEUTRAL  = 11'd992;
localparam SAFE_THROTTLE = 11'd172;
localparam THROTTLE_CH   = 4'd2;

reg [5:0]byte_counter = 0;
reg state = WAIT;
reg [2:0]state_2 = IDLE;
reg [1:0]state_3 = LOAD;
reg next_state;
reg [2:0]next_state_2;
reg [1:0] next_state_3;
reg [7:0]checksum = 0;
reg [10:0]staging_buf[0:15];
reg [10:0]live_register[0:15];
integer i;
reg [175:0]array;
integer y;
integer j;
reg [7:0]frame[0:24];
reg [7:0]timer = 0;
reg start;
reg busy;
reg tx;
reg [7:0] data_latch;
reg [7:0] data_in;
reg [3:0]data_counter = 0;
reg load_enable;
reg [4:0]byte_index = 0;
reg [15:0]gap_timer = 0;
reg go = 0;
reg busy_prev = 0;
reg [20:0]failsafe_counter = 0;

wire timer_done;
wire packet_valid = valid && state == READ && byte_counter == 32 && checksum == data_byte;
wire failsafe = failsafe_counter >= 21'd1199999;

assign sbus_out = ~tx;

always @(*) begin
	case (state)
		WAIT: begin
			next_state = (valid && data_byte == 8'hAA) ? READ : WAIT;
		end
		READ: begin
			next_state = (valid && byte_counter == 32) ? WAIT : READ;
		end
		default: next_state = WAIT;
	endcase
end

always @(posedge clk) begin
	state <= next_state;
    state_2 <= next_state_2;
    state_3 <= next_state_3;
end

always @(posedge clk) begin
	if (valid && state == READ) begin
		byte_counter <= byte_counter + 1;
		checksum <= checksum ^ data_byte;
		if (byte_counter == 32 && checksum == data_byte) begin
			for (i = 0; i < 16; i = i + 1)
				live_register[i] <= staging_buf[i];
		end
		if (byte_counter < 32 && byte_counter[0] == 0)
			staging_buf[byte_counter >> 1][7:0] <= data_byte;
		else if (byte_counter < 32)
			staging_buf[byte_counter >> 1][10:8] <= data_byte[2:0];
	end else if (state == WAIT) begin
		byte_counter <= 0;
		checksum <= 0;
	end
end

always @(*) begin
    for (y = 0; y < 16; y = y + 1) begin
        if (failsafe)
            array[11*y +: 11] = (y == THROTTLE_CH) ? SAFE_THROTTLE : SAFE_NEUTRAL;
        else
            array[11*y +: 11] = live_register[y];
    end
end

always @(posedge clk) begin
    if (load_enable) begin
    	for (j = 0; j < 22; j = j +1) 
    		frame[j + 1] <= array[8*j +: 8];
    	frame[0] <= 8'h0F;
    	frame[23] <= failsafe ? 8'h10 : 8'h00;
    	frame[24] <= 8'h00;
    end
end


always @(*) begin
	case (state_2)
        IDLE: begin
            next_state_2 = start ? SEND_START_BIT: IDLE;
            tx = 1;
            busy = 0;
        end
        SEND_START_BIT: begin
            next_state_2 = timer_done ? SEND_DATA_BIT : SEND_START_BIT;
            tx = 0;
            busy = 1;
        end
        SEND_DATA_BIT: begin
            next_state_2 = (timer_done && data_counter == 4'd7) ? SEND_PARITY_BIT : SEND_DATA_BIT;
            tx = data_latch[data_counter];
            busy = 1;

        end
        SEND_PARITY_BIT: begin
            next_state_2 = (timer_done) ? SEND_STOP_BIT : SEND_PARITY_BIT;
            busy = 1;
            tx = ^data_latch;
        end
        SEND_STOP_BIT: begin
            next_state_2 = (timer_done && data_counter == 4'd10) ? IDLE : SEND_STOP_BIT;
            tx = 1;
            busy = 1;
        end
        default: begin
            next_state_2 = IDLE;
            tx = 1;
        end
	endcase
end

always @(posedge clk) begin
	if(state_2 == IDLE)
		timer <= 0;
	else if (timer == 7'd119)
		timer <= 0;
	else
		timer <= timer + 1;
	if (state_2 == IDLE || state_2 == SEND_START_BIT)
		data_counter <= 0;
	else if (timer_done)
		data_counter <= data_counter + 1;
end 
assign timer_done = (timer == 7'd119);

always @(posedge clk) begin
    if (state_2 == IDLE && start)
        data_latch <= data_in;
end

always @(*) begin 
    case(state_3) 
        LOAD: begin
            next_state_3 = SEND;
            load_enable = 1;
        end
        SEND: begin
            next_state_3 = WAIT_BYTE;
            load_enable = 0;
        end
        WAIT_BYTE: begin
            if (go == 1)
                next_state_3 = (byte_index == 25) ? GAP : SEND;
            else
                next_state_3 = WAIT_BYTE;
            load_enable = 0;
        end
        GAP: begin
            next_state_3 = (gap_timer == 47999 ) ? LOAD : GAP;
            load_enable = 0;
        end
        default: begin
            next_state_3 = LOAD;
            load_enable = 0;
        end
    endcase
end

always @ (posedge clk) begin
    go <= 0;
    start <= 0;
    busy_prev <= busy;
    if (state_3 == LOAD)
        byte_index <= 0;
    if (state_3 == GAP)
        gap_timer <= gap_timer + 1;
    else 
        gap_timer <= 0;
    if (state_3 == SEND) begin
        start <= 1;
        data_in <= frame[byte_index];
        byte_index <= byte_index + 1;
    end
    if (state_3 == WAIT_BYTE) begin
        if (busy_prev == 1 && busy == 0) begin
            go <= 1;
        end
    end

end

always @(posedge clk) begin
    if (packet_valid) begin
        failsafe_counter <= 0;
    end
    else if (failsafe_counter < 21'd1199999)begin
        failsafe_counter <= failsafe_counter + 1;
    end
end

endmodule 

