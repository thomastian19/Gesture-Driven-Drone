# serial_output.py  (PPM version)
# Sends gesture channel values to the FPGA as 34-byte packets over USB-UART.
#
# Packet format (must match the FPGA parser exactly):
#   Byte 0:        header = 0xAA
#   Bytes 1..32:   16 channels x 2 bytes each, LITTLE-ENDIAN (low byte, high byte)
#                  Each channel is an 11-bit value (0..2047), upper 5 bits of the
#                  high byte are zero.
#   Byte 33:       checksum = XOR of bytes 1..32
#
# Channel ordering (conventional):
#   ch0 = roll, ch1 = pitch, ch2 = throttle, ch3 = yaw
#   ch4..ch15 = unused (filled with neutral)
#
# IMPORTANT (PPM): The FPGA PPM generator uses each channel value DIRECTLY as
# microseconds (1000..2000us, 1500 center). So we send the raw 1000..2000
# gesture values with NO SBUS rescaling. The FPGA computes the pulse gap as
# (value * 12) - 3600 cycles at 12 MHz. Sending values below ~300 would
# underflow that math, so we clamp to the valid 1000..2000 PPM range.

import serial

# ── Configuration ─────────────────────────────────────────────
PORT = 'COM4'          # <-- set to your FPGA's UART COM port (Device Manager)
BAUD = 115200          # must match the FPGA's uart_rx baud

HEADER = 0xAA

# Conventional channel slots
CH_ROLL     = 0
CH_PITCH    = 1
CH_THROTTLE = 2
CH_YAW      = 3

# PPM value range (microseconds). Values are sent through UNCHANGED and used
# by the FPGA directly as the channel period in microseconds.
PPM_MIN     = 1000     # minimum / -100%
PPM_MAX     = 2000     # maximum / +100%
PPM_NEUTRAL = 1500     # center

# ── Value conditioning ────────────────────────────────────────
def clamp_ppm(value):
    """Clamp to the valid 1000..2000 PPM (microsecond) range."""
    return int(max(PPM_MIN, min(PPM_MAX, round(value))))

# ── Packet building ───────────────────────────────────────────
def build_packet(throttle, yaw, pitch, roll):
    """
    Build the 34-byte packet from four gesture channel values
    (each in the 1000..2000 range, used directly as PPM microseconds).
    Returns a bytes object.
    """
    # Initialize all 16 channels to neutral (1500us)
    channels = [PPM_NEUTRAL] * 16

    # Place the four active controls in their conventional slots.
    # No rescaling: the 1000..2000 value IS the PPM value.
    channels[CH_ROLL]     = clamp_ppm(roll)
    channels[CH_PITCH]    = clamp_ppm(pitch)
    channels[CH_THROTTLE] = clamp_ppm(throttle)
    channels[CH_YAW]      = clamp_ppm(yaw)

    # Build the body: 16 channels x 2 bytes, little-endian
    body = bytearray()
    for ch in channels:
        low  = ch & 0xFF          # low 8 bits
        high = (ch >> 8) & 0x07   # high 3 bits (11-bit value)
        body.append(low)
        body.append(high)

    # Checksum = XOR of all 32 body bytes
    checksum = 0
    for b in body:
        checksum ^= b

    # Assemble full packet
    packet = bytearray()
    packet.append(HEADER)
    packet.extend(body)
    packet.append(checksum)
    return bytes(packet)

# ── Serial port management ────────────────────────────────────
class FPGALink:
    def __init__(self, port=PORT, baud=BAUD):
        try:
            self.ser = serial.Serial(port, baud, timeout=0)
            self.connected = True
        except serial.SerialException:
            print(f"WARNING: could not open {port} - running without FPGA output")
            self.ser = None
            self.connected = False

    def send(self, throttle, yaw, pitch, roll):
        if not self.connected:
            return
        packet = build_packet(throttle, yaw, pitch, roll)
        self.ser.write(packet)

    def close(self):
        if self.connected:
            self.ser.close()


# ── Standalone test (run this file directly to test without the camera) ──
if __name__ == "__main__":
    import time
    link = FPGALink()
    print(f"Sending test packets on {PORT} at {BAUD} baud. Ctrl+C to stop.")
    try:
        # Sweep throttle up and down so you can watch the PPM throttle
        # channel (ch2) gap width change on the logic analyzer / channel monitor.
        t = 1000
        direction = 10
        while True:
            link.send(throttle=t, yaw=1500, pitch=1500, roll=1500)
            t += direction
            if t >= 2000 or t <= 1000:
                direction = -direction
            time.sleep(0.02)   # ~50 Hz
    except KeyboardInterrupt:
        link.close()
        print("\nClosed.")