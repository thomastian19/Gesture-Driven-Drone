# 🛸👋 Gesture-Driven-Drone

https://github.com/user-attachments/assets/b02ccb57-5160-4b97-a7e9-b1af7947c300 


Fly a quadcopter with your hand gestures. A webcam tracks hand position and an FPGA translates those movements into RC control channels that drive a drone.

The heart of this project is in the RTL design on the FPGA. It receives data over UART, validates and
unpacks it, and generates a bit-accurate, precisely-timed RC signal with a
watchdog to force failsafe values if packets stop arriving.

## 📐 System Design

<img width="822" height="287" alt="image" src="https://github.com/user-attachments/assets/e55c1cf1-b206-47cb-b9f2-087a54e51e2b" />


Everything from the webcam to the FPGA output was designed and verified from
scratch. The radio and drone are commercial hardware.

## 📟 FPGA Design

I used an Cmod A7-35T (Xilinx Artix-7) board with all RTL written and verified in Verilog using functional testbenches. All timing was done using the 12Mhz clock and counters, no MMCMs. 

### Packet Interface and Parser

The laptop sends a fixed 34-byte packet: a 0xAA header, 16 channels ×
2 bytes (little-endian, 11-bit values), and an XOR checksum.

The uart reciever (rtl/uart_rx.v) decodes the serial rx line (8N1 at 115200 baud) into parallel bytes. A 4-state FSM (IDLE → FIRST → RECEIVE_DATA → LAST) detects the start bit, waits half a bit period to align to bit centers, then samples each of the 8 data bits mid-bit. It shifts them LSB-first into a byte. On a valid stop bit it outputs the assembled byte on data_out and pulses valid high for one cycle to signal a byte is ready. 

The parser (rtl/parser.v) is a small FSM (WAIT -> BEGIN). BEGIN starts when the valid bit is recieved; then it takes bytes
from the UART, accumulates the checksum, and stages the channel data.
The staged channels are copied into the live
registers only on the cycle the checksum validates: 

```SystemVerilog
if (byte_counter == 32 && checksum == data_byte) begin
    for (i = 0; i < 16; i = i + 1)
        live_register[i] <= staging_buf[i];
end
```

This guarantees the output stage never reads a half-updated frame: either a
whole valid packet lands, or the previous values are held.

### Output Generation
My original design recieved the UART packets and sent the data in SBUS baud and format. However, after finding the SBUS input on the radio require a solder (which I didn't have) and wasn't well documented, I chose to change my design to send the data in PPM. The radio could recieve this easily over a 3.5 mm aux port. 
Now I have designs for two output protocols:


* SBUS (rtl/parser.v) - an inverted 8E2 serial signal at
100 kBaud (Futaba spec: 8 data bits, even parity, 2 stop bits, idle-low). A
byte-transmitter FSM serializes each frame byte, and a frame sequencer emits
the 25-byte SBUS frame (header, 22 packed data bytes, flags, footer) followed
by an gap, repeating continuously.

* PPM (rtl/parser_ppm.v) - a time-encoded protocol with
a 300 µs pulse followed by a gap whose length encodes each channel value
(1000–2000 µs), for 8 channels. A frame-length
timer holds the total period constant so the sync gap fills the necessary gap to meet 22.5 ms frame length.
The interesting thing here was making sure sync gap a variable time determined exclusively for each data set.




## ✅ Verification

## 👁️ Vision and Control

##

 📡 Radio and Drone Integration
