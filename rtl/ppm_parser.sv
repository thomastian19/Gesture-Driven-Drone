module parser(
	input [7:0]data_byte,
	input valid,
	input clk,
	output reg ppm_out);

localparam WAIT = 1'b0;
localparam READ = 1'b1;
localparam PULSE = 2'b00;
localparam GAP = 2'b01;
localparam SYNC = 2'b10;

localparam SAFE_THROTTLE = 11'd1000;
localparam SAFE_NEUTRAL  = 11'd1500;   // center (PPM units)
localparam THROTTLE_CH   = 4'd2;       // conventional throttle channel

reg [5:0]byte_counter = 0;
reg state = WAIT;
reg [1:0]state_2 = PULSE;
reg next_state;
reg [1:0]next_state_2;
reg [7:0]checksum = 0;
reg [10:0]staging_buf[0:15];
reg [10:0]live_register[0:15];
integer i;
reg [175:0]array;
integer y;
reg [14:0]timer = 0; 
reg [18:0] frame_timer = 0; 
reg [3:0] ch_counter = 0; 
reg [10:0] channel_data = 0; 
reg [20:0]failsafe_counter = 0;

wire packet_valid = valid && state == READ && byte_counter == 32 && checksum == data_byte;
wire failsafe = (failsafe_counter >= 21'd1199999);

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
	case (state_2)
        PULSE: begin
            if (timer == 3599)
                next_state_2 = (ch_counter < 8) ? GAP : SYNC;
            else
                next_state_2 = PULSE;
            ppm_out = 1;
        end
        GAP: begin
            next_state_2 = (timer == ((channel_data * 12) - 3601)) ? PULSE : GAP;
            ppm_out = 0;
        end
        SYNC: begin
            next_state_2 = (frame_timer == 19'd269999) ? PULSE : SYNC;
            ppm_out = 0;
        end
        default: begin
            next_state_2 = PULSE;
            ppm_out = 0;
        end
	endcase
end

always @(posedge clk) begin
    if ((state_2 == PULSE && timer == 3599) || (state_2 == GAP && (timer == ((channel_data * 12) - 3601))) || (state_2 == SYNC && (frame_timer == 19'd269999))) begin
        timer <= 0;
    end
    else
        timer <= timer + 1;
    if (state_2 == SYNC) 
        ch_counter <= 0;
    if (state_2 == GAP && (timer == ((channel_data * 12) - 3601)))
        ch_counter <= ch_counter + 1;
    if (state_2 == SYNC && frame_timer == 19'd269999)
        frame_timer <= 0;
    else
        frame_timer <= frame_timer + 1;
end

always @(*) begin
    if (failsafe)
        channel_data = (ch_counter == THROTTLE_CH) ? SAFE_THROTTLE : SAFE_NEUTRAL;
    else
        channel_data = live_register[ch_counter];
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

