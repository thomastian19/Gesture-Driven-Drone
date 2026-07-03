# 🛸👋 Gesture-Driven-Drone

https://github.com/user-attachments/assets/b02ccb57-5160-4b97-a7e9-b1af7947c300 


Fly a quadcopter with your hand gestures. A webcam tracks hand position and an FPGA translates those movements into RC control channels that drive a drone.

The heart of this project is in the RTL design on the FPGA. It receives data over UART, validates and
unpacks it, and generates a bit-accurate, precisely-timed RC signal with a
watchdog to force failsafe values if packets stop arriving.

## 📐 System Architecture

<img width="822" height="287" alt="image" src="https://github.com/user-attachments/assets/e55c1cf1-b206-47cb-b9f2-087a54e51e2b" />


Everything from the webcam to the FPGA output was designed and verified from
scratch; the radio and drone are commercial hardware integrated into the chain.

## 📟 FPGA Design

## ✅ Verification

## 👁️ Vision and Control

##

 📡 Radio and Drone Integration
