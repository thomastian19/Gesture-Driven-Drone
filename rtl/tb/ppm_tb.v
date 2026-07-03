`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/28/2026 09:36:01 PM
// Design Name: 
// Module Name: ppm_tb
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

module ppm_tb;

    reg        clk;
    reg  [7:0] data_byte;
    reg        valid;
    wire       ppm_out;

    parser dut (
        .data_byte(data_byte),
        .valid    (valid),
        .clk      (clk),
        .ppm_out  (ppm_out)
    );

    // ~12 MHz clock: period ~83.33ns, half ~41.67ns
    initial clk = 0;
    always #42 clk = ~clk;

    // Cycle counter for measuring durations in clk cycles
    integer cycle_count;
    initial cycle_count = 0;
    always @(posedge clk) cycle_count = cycle_count + 1;

    task send_packet_byte(input [7:0] b);
        begin
            @(negedge clk);
            data_byte = b;
            valid     = 1'b1;
            @(negedge clk);
            valid     = 1'b0;
            @(negedge clk);
            @(negedge clk);
        end
    endtask

    integer k;
    reg [10:0] ch [0:15];
    reg [7:0]  payload [0:31];
    reg [7:0]  csum;

    // Send a packet with channels 0..7 set to known PPM values,
    // 8..15 set to neutral.
    task send_known_packet;
        begin
            ch[0] = 11'd1000;   // ch0: min
            ch[1] = 11'd1500;   // ch1: center
            ch[2] = 11'd2000;   // ch2: max (throttle slot, but not failsafe here)
            ch[3] = 11'd1250;   // ch3
            ch[4] = 11'd1500;
            ch[5] = 11'd1500;
            ch[6] = 11'd1500;
            ch[7] = 11'd1750;
            for (k = 8; k < 16; k = k + 1) ch[k] = 11'd1500;

            for (k = 0; k < 16; k = k + 1) begin
                payload[k*2]     = ch[k][7:0];
                payload[k*2 + 1] = {5'b0, ch[k][10:8]};
            end
            csum = 8'h00;
            for (k = 0; k < 32; k = k + 1)
                csum = csum ^ payload[k];

            send_packet_byte(8'hAA);
            for (k = 0; k < 32; k = k + 1)
                send_packet_byte(payload[k]);
            send_packet_byte(csum);
        end
    endtask

    // ── Measurement: detect edges on ppm_out and report durations ──
    reg        prev_ppm;
    integer    last_edge_cycle;
    integer    pulse_count;

    initial begin
        prev_ppm = 0;
        last_edge_cycle = 0;
        pulse_count = 0;
    end

    // Track rising/falling edges of ppm_out and print segment lengths
    always @(posedge clk) begin
        if (ppm_out !== prev_ppm) begin
            if (ppm_out == 1'b1) begin
                // rising edge: a low segment (gap or sync) just ended
                $display("  t=%0t  LOW  lasted %0d cycles (%0d us)",
                         $time, cycle_count - last_edge_cycle,
                         (cycle_count - last_edge_cycle)/12);
            end else begin
                // falling edge: a high segment (pulse) just ended
                $display("  t=%0t  HIGH lasted %0d cycles (%0d us)  [pulse #%0d]",
                         $time, cycle_count - last_edge_cycle,
                         (cycle_count - last_edge_cycle)/12, pulse_count);
                pulse_count = pulse_count + 1;
            end
            last_edge_cycle = cycle_count;
            prev_ppm = ppm_out;
        end
    end

    initial begin
        data_byte = 0;
        valid     = 0;
        #500;

        $display("=== Sending known packet ===");
        $display("  ch0=1000(min) ch1=1500(ctr) ch2=2000(max) ch3=1250");
        $display("  ch4..6=1500 ch7=1750");
        $display("  Expected: pulse=3600cyc(300us), gap=(val*12 - 3600)cyc");
        $display("    ch0 gap: 1000*12-3600 = 8400cyc (700us)");
        $display("    ch1 gap: 1500*12-3600 = 14400cyc (1200us)");
        $display("    ch2 gap: 2000*12-3600 = 20400cyc (1700us)");
        $display("    full frame should be 270000cyc (22500us)");
        send_known_packet;

        $display("=== Watching PPM output (one+ full frames) ===");
        // One frame is ~22.5ms. Watch ~2.5 frames = ~56ms.
        // (Long sim, but you said sims run fast for you.)
        #56000000;

        $display("=== done ===");
        $finish;
    end

    // ── Frame period check: measure SYNC->first rising edges ──
    // Detect frame boundaries by spotting the long SYNC low.
    // (Manual inspection from the printed LOW durations is also fine:
    //  the long LOW is the sync gap.)

endmodule
