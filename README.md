# 🛸👋 Gesture-Driven-Drone

{video}

Fly a quadcopter with your hand gestures. A webcam tracks hand position and an FPGA translates those movements into RC control channels that drive a drone.

The heart of this project is in the RTL design on the FPGA. It receives data over UART, validates and
unpacks it, and generates a bit-accurate, precisely-timed RC signal with a
watchdog to force failsafe values if packets stop arriving.

# System Architecture

{Block Design}

Everything from the webcam to the FPGA output was designed and verified from
scratch; the radio and drone are commercial hardware integrated into the chain.

# FPGA Design

# Verification

# Vision and Control

# Radio and Drone Integration
