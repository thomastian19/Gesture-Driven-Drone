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

I used an Cmod A7-35T (Xilinx Artix-7) board with all RTL written and verified in Verilog using functional testbenches. All timing was done using the 12Mhz clock and counters, no MMCMs. My origin design recieved the UART packets and sent the data in SBUS baud and format. However, after finding the SBUS input on the radio require a solder (which I didn't have) and wasn't well documented, I chose to change my design to send the data in PPM. The radio could recieve this easily over a 3.5 mm aux port.

### Packet Interface and Parser

The laptop sends a fixed 34-byte packet: a 0xAA header, 16 channels ×
2 bytes (little-endian, 11-bit values), and an XOR checksum.

The parser (rtl/parser.v) is a small FSM that receives bytes
from the UART, accumulates the checksum, and stages the channel data. Crucially,
the staged channels are committed atomically — copied into the live
registers only on the single cycle where the checksum validates:

## ✅ Verification

## 👁️ Vision and Control

##

 📡 Radio and Drone Integration
