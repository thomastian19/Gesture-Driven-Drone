`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/21/2026 06:16:55 PM
// Design Name: 
// Module Name: parser_sbus
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

module watchdog_tb;

    reg        clk;
    reg  [7:0] data_byte;
    reg        valid;
    wire       sbus_out;

    parser dut (
        .data_byte(data_byte),
        .valid    (valid),
        .clk      (clk),
        .sbus_out (sbus_out)
    );

    initial clk = 0;
    always #42 clk = ~clk;

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
    reg [7:0] payload [0:31];
    reg [7:0] csum;

    task send_good_packet;
        begin
            for (k = 0; k < 16; k = k + 1)
                ch[k] = (k*131 + 7) & 11'h7FF;
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

    initial begin
        data_byte = 0;
        valid     = 0;
        #200;

        // ─────────────────────────────────────────────────────────
        // 1. Send a good packet -> failsafe should be LOW, counter reset
        // ─────────────────────────────────────────────────────────
        $display("=== Sending a good packet ===");
        send_good_packet;
        #1000;
        $display("  after packet: failsafe=%b  counter=%0d",
                 dut.failsafe, dut.failsafe_counter);
        if (dut.failsafe === 1'b0) $display("  OK: failsafe low after valid packet");
        else $display("  WRONG: failsafe high right after a valid packet");

        // ─────────────────────────────────────────────────────────
        // 2. Stop sending packets -> counter climbs, failsafe asserts
        //    (threshold lowered to 2000 for sim; ~167us)
        // ─────────────────────────────────────────────────────────
        $display("=== Stop sending. Waiting for failsafe to assert... ===");
        wait (dut.failsafe == 1'b1);
        $display("  failsafe asserted at t=%0t  counter=%0d",
                 $time, dut.failsafe_counter);

        // Check the safe values are now feeding the packer
        #100;
        $display("  packed throttle ch (array[11*2 +:11]) = %0d (expect 172)",
                 dut.array[11*2 +: 11]);
        $display("  packed ch0 (array[10:0]) = %0d (expect 992)",
                 dut.array[10:0]);

        // ─────────────────────────────────────────────────────────
        // 3. Send another good packet -> failsafe should clear
        // ─────────────────────────────────────────────────────────
        $display("=== Sending another good packet -> failsafe should clear ===");
        send_good_packet;
        #1000;
        $display("  after recovery packet: failsafe=%b  counter=%0d",
                 dut.failsafe, dut.failsafe_counter);
        if (dut.failsafe === 1'b0) $display("  OK: failsafe cleared after new valid packet");
        else $display("  WRONG: failsafe still high after recovery packet");

        // Check live values are back in the packer
        #100;
        $display("  packed ch0 (array[10:0]) = %0d (expect %0d, the live value)",
                 dut.array[10:0], ch[0]);

        $display("=== done ===");
        $finish;
    end

endmodule