# 🛸👋 Gesture-Driven-Drone
Fly a quadcopter with your hand gestures. A webcam tracks hand position and an FPGA translates those movements into RC control channels that drive a drone.

The heart of this project is in the RTL design on the FPGA. It receives control data over UART, validates and
unpacks it, and generates a bit-accurate, precisely-timed RC signal with a
watchdog to force failsafe values if packets stop arriving.
