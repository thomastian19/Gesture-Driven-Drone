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

The [uart reciever](rtl/uart_rx.v) decodes the serial rx line (8N1 at 115200 baud) into parallel bytes. A 4-state FSM (IDLE → FIRST → RECEIVE_DATA → LAST) detects the start bit, waits half a bit period to align to bit centers, then samples each of the 8 data bits mid-bit. It shifts them LSB-first into a byte. On a valid stop bit it outputs the assembled byte on data_out and pulses valid high for one cycle to signal a byte is ready. 

The [parser](rtl/parser.v) is a small FSM (WAIT -> BEGIN). BEGIN starts when the valid bit is recieved; then it takes bytes
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


* [SBUS](rtl/parser.v) - an inverted 8E2 serial signal at
100 kBaud (Futaba spec: 8 data bits, even parity, 2 stop bits, idle-low). A
byte-transmitter FSM serializes each frame byte, and a frame sequencer emits
the 25-byte SBUS frame (header, 22 packed data bytes, flags, footer) followed
by an gap, repeating continuously.

* [PPM](rtl/parser_ppm.v) - a time-encoded protocol with
a 300 µs pulse followed by a gap whose length encodes each channel value
(1000–2000 µs), for 8 channels. A frame-length
timer holds the total period constant so the sync gap fills the necessary gap to meet 22.5 ms frame length.
The interesting thing here was making sure sync gap a variable time determined exclusively for each data set.

### Hardware Watchdog

A watchdog [counter](rtl/parser.v) resets on every
checksum-valid packet and counts up otherwise. If no valid packet arrives for
100 ms, it asserts a failsafe that forces the channels to safe values (throttle
minimum, attitude centered). This means a laptop crash, unplugged cable, or stalled vision pipeline puts the
craft into a safe state rather than holding the last command. 

This was especially because by radio's trainer port was designed for 3.5 mm TS cable while I was using a 3.55 TRS cable. 
While the connection worked, it wasn't always stable and would lose connection occasinally. The failsafe prevented drone damage.


## ✅ Verification

**Staged Simulation** I wrote [testbenches](rtl/tb) with functional coverage to exercise each
stage: UART receive, packet parsing and checksum rejection, bit-packing, full frame generation, and watchdog assert/recover. Edge cases (corrupted
packets, frame boundaries, failsafe timeout and recovery) were tested
explicitly. This approach helped me catch Several bugs including FSM timing, an off-by-one in frame counting, and a
gap-duration miscalculation. 

**Hardware Verification** 
The FPGA output was captured with a Saleae logic
analyzer. Shoutout my dad for letting me borrow it from his lab. SBUS frames were decoded and
confirmed byte-for-byte, including the failsafe frame (flags = 0x10) and
normal frames driven by live data. PPM pulse widths and gaps were measured
directly against the expected ms values.

**Saleae Logic 2 Software View**

<figure>
  <img width="795" height="251" alt="Screenshot 2026-06-25 200848" src="https://github.com/user-attachments/assets/ab557851-ee99-4ec2-9f98-e1ba3e19952b" />
    <img width="212" height="260" alt="image" src="https://github.com/user-attachments/assets/02c5de60-c44f-494f-bf05-a63873d5dcd2" />
    <br>
  <figcaption><i>Start byte = x0F, Flag byte = x10, End Byte = x00</i></figcaption>
</figure>


## 👁️ Vision and Control


https://github.com/user-attachments/assets/45296893-c20b-47cb-b9c6-d8038abad5e6






The Python side (python/gesture_control.py,
python/serial_output.py) handles tracking and
mapping:

* Hand tracking — MediaPipe tracks two hands; the left controls throttle
and yaw, the right controls pitch and roll, mapped from hand position in
defined regions.

* Neutral deadzone — a center bubble for each hand snaps its channels to
neutral, with throttle scaled from the midpoint upward only.

* Activation gate — the system holds safe neutral values until both hands
are deliberately centered together, so nothing is commanded while you're ready.

* Smoothing & failsafe — I used the Exponential Moving Average (EMA) formula to reduce jitter.
After several test runs and crashes I settled on α = 0.3.

&nbsp; $SmoothedValue = α * ChannelValue + (1 - α) * PreviousSmoothedValue$


## 📡 Radio and Drone Integration

One end of the 3.5 mm TRS cable went into the radio. I cut the other end, separated the wires, identified the ring matchings with
a multimeter in continuity mode, and hooked it up to the FPGA with a small breadboard.

The FPGA's output drives a RadioMaster Pocket through its the caple to it's trainer
input, configured as a master trainer so the incoming channels drive the model.
A physical switch toggles the trainer on/off, providing an manual
override. The Pocket transmits to a BetaFPV Air65 over ExpressLRS; Betaflight
is configured with a CRSF receiver and an arm switch. 


<br>
<img width="352" height="263" alt="image" src="https://github.com/user-attachments/assets/4c495723-afc9-4587-9086-cdacf6be7364" />


