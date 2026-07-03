import cv2
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
import urllib.request
import os
from serial_output import FPGALink

# ── Download the model if needed ──────────────────────────────
MODEL_PATH = "hand_landmarker.task"
if not os.path.exists(MODEL_PATH):
    print("Downloading hand landmarker model...")
    url = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task"
    urllib.request.urlretrieve(url, MODEL_PATH)

# ── Set up the landmarker for video, tracking up to 2 hands ───
base_options = python.BaseOptions(model_asset_path=MODEL_PATH)
options = vision.HandLandmarkerOptions(
    base_options=base_options,
    running_mode=vision.RunningMode.VIDEO,
    num_hands=2,
)
landmarker = vision.HandLandmarker.create_from_options(options)

# ── Tunable parameters ────────────────────────────────────────
# Vertical active range: the middle 75% of frame height is "live".
V_MARGIN = 0.125            # 12.5% margin top and bottom -> 75% active
V_MIN, V_MAX = V_MARGIN, 1.0 - V_MARGIN

# Vertical center of the active band -> neutral point.
V_CENTER = (V_MIN + V_MAX) / 2.0   # = 0.5

# Horizontal active fraction WITHIN each hand's half.
H_ACTIVE = 0.6             # use middle 60% of each half

# Left hand's half spans x in [0.0, 0.5], center 0.25.
LEFT_CENTER = 0.25
LEFT_HALF_W = 0.5
LEFT_X_MIN = LEFT_CENTER - (LEFT_HALF_W * H_ACTIVE) / 2
LEFT_X_MAX = LEFT_CENTER + (LEFT_HALF_W * H_ACTIVE) / 2

# Right hand's half spans x in [0.5, 1.0], center 0.75.
RIGHT_CENTER = 0.75
RIGHT_HALF_W = 0.5
RIGHT_X_MIN = RIGHT_CENTER - (RIGHT_HALF_W * H_ACTIVE) / 2
RIGHT_X_MAX = RIGHT_CENTER + (RIGHT_HALF_W * H_ACTIVE) / 2

# Smoothing factor for the exponential moving average (0..1).
# Higher = more responsive/jittery, lower = smoother/laggier.
# Lowered from 0.4 -> 0.3 for less sensitivity (smoother, a bit more lag).
ALPHA = 0.3

# Failsafe throttle decay: how many channel-units to drop per frame
# when both hands are lost. At ~30 fps, 15/frame ≈ 1000 units in ~2s,
# i.e. throttle bleeds from full to minimum over roughly two seconds.
THROTTLE_DECAY = 15

# Channel limits
CH_MIN = 1000
CH_MID = 1500
CH_MAX = 2000

# Neutral deadzone radius (pixels). When the palm is within this distance
# of the hand's center dot, that hand's channels snap to neutral
# (throttle = CH_MIN/zero, attitude = CH_MID). Matches the drawn ring.
CENTER_SNAP_PX = 25

# ── Channel mapping helper ────────────────────────────────────
def to_channel(value, in_min, in_max, invert=False, out_min=CH_MIN, out_max=CH_MAX):
    """
    Map `value` from [in_min, in_max] to [out_min, out_max], clamped.
    The midpoint of the input range maps to the midpoint of the output
    range (1500), so neutral sits at the center of the active span.
    """
    v = max(in_min, min(in_max, value))
    norm = (v - in_min) / (in_max - in_min)
    if invert:
        norm = 1.0 - norm
    return int(out_min + norm * (out_max - out_min))

def throttle_from_top_half(palm_y):
    """
    Throttle scales from the MIDPOINT upward only:
      - palm at or BELOW vertical center (palm_y >= V_CENTER) -> CH_MIN (zero throttle)
      - palm rising from center to the TOP (V_CENTER -> V_MIN) -> CH_MIN -> CH_MAX
    Lower screen y = higher up = more throttle.
    """
    if palm_y >= V_CENTER:
        return CH_MIN
    # palm_y is between V_MIN (top) and V_CENTER (middle).
    # Map V_CENTER -> 0.0 (min) and V_MIN -> 1.0 (max).
    frac = (V_CENTER - palm_y) / (V_CENTER - V_MIN)
    frac = max(0.0, min(1.0, frac))
    return int(CH_MIN + frac * (CH_MAX - CH_MIN))

# Landmark index for the middle-finger MCP (palm center). Stable point.
PALM = 9

# ── Persistent smoothed channel values (survive across frames) ──
smooth_throttle = CH_MIN
smooth_yaw      = CH_MID
smooth_pitch    = CH_MID
smooth_roll     = CH_MID

# ── Activation gate ───────────────────────────────────────────
# The system does NOT send live gesture values until BOTH hands have
# been placed in their center bubbles at the same time at least once.
# Until then, only safe neutral values (throttle zero, attitude center)
# are sent, so nothing happens while you move your hands into position.
# Once activated, it stays active WHILE at least one hand is present.
# If BOTH hands leave the frame, the gate resets: the system returns to
# holding safe neutral values and will not send live values again until
# both hands touch their center bubbles together once more.
activated = False

fpga = FPGALink()

cap = cv2.VideoCapture(0)
timestamp_ms = 0

while cap.isOpened():
    success, frame = cap.read()
    if not success:
        continue

    # Mirror so it behaves like a mirror (intuitive for the user)
    frame = cv2.flip(frame, 1)
    h, w, _ = frame.shape

    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    result = landmarker.detect_for_video(mp_image, timestamp_ms)
    timestamp_ms += 33

    # Failsafe defaults (used as raw targets when a hand is present
    # but a channel isn't driven this frame)
    throttle = CH_MIN
    yaw      = CH_MID
    pitch    = CH_MID
    roll     = CH_MID

    left_found = False
    right_found = False

    # Pixel positions of each hand's neutral center dot.
    left_dot  = (int(LEFT_CENTER  * w), int(V_CENTER * h))
    right_dot = (int(RIGHT_CENTER * w), int(V_CENTER * h))

    # Track palm positions and whether each hand is inside its deadzone.
    left_palm_px  = None
    right_palm_px = None
    left_centered  = False
    right_centered = False

    # Assign each detected hand to a zone by SCREEN POSITION, not by
    # MediaPipe's Left/Right label. MediaPipe's handedness flickers and can
    # briefly mislabel or double-label hands, which caused control glitches.
    # A hand in the left half drives throttle+yaw; a hand in the right half
    # drives pitch+roll. Either physical hand works in either zone, and both
    # zones can be driven at once (one hand in each half).
    #
    # If two hands land in the same half (both in the left, say), the one
    # closest to that half's center dot wins that zone, so a stray second
    # hand doesn't fight it.
    if result.hand_landmarks:
        left_zone_hand  = None   # (px, py, dist_to_left_center)
        right_zone_hand = None   # (px, py, dist_to_right_center)

        for hand in result.hand_landmarks:
            palm = hand[PALM]
            px, py = int(palm.x * w), int(palm.y * h)

            if px < (w // 2):
                # Left half -> left (throttle+yaw) zone
                d = (px - left_dot[0])**2 + (py - left_dot[1])**2
                if left_zone_hand is None or d < left_zone_hand[2]:
                    left_zone_hand = (px, py, d)
            else:
                # Right half -> right (pitch+roll) zone
                d = (px - right_dot[0])**2 + (py - right_dot[1])**2
                if right_zone_hand is None or d < right_zone_hand[2]:
                    right_zone_hand = (px, py, d)

        # ── Left zone: throttle + yaw ──
        if left_zone_hand is not None:
            px, py, _ = left_zone_hand
            left_found = True
            left_palm_px = (px, py)
            dx = px - left_dot[0]
            dy = py - left_dot[1]
            left_centered = (dx * dx + dy * dy) <= (CENTER_SNAP_PX * CENTER_SNAP_PX)

            if left_centered:
                throttle = CH_MIN
                yaw      = CH_MID
            else:
                throttle = throttle_from_top_half(py / h)
                yaw      = to_channel(px / w, LEFT_X_MIN, LEFT_X_MAX)
            cv2.circle(frame, (px, py), 10, (255, 100, 0), -1)

        # ── Right zone: pitch + roll ──
        if right_zone_hand is not None:
            px, py, _ = right_zone_hand
            right_found = True
            right_palm_px = (px, py)
            dx = px - right_dot[0]
            dy = py - right_dot[1]
            right_centered = (dx * dx + dy * dy) <= (CENTER_SNAP_PX * CENTER_SNAP_PX)

            if right_centered:
                pitch = CH_MID
                roll  = CH_MID
            else:
                pitch = to_channel(py / h, V_MIN, V_MAX, invert=True)
                roll  = to_channel(px / w, RIGHT_X_MIN, RIGHT_X_MAX)
            cv2.circle(frame, (px, py), 10, (0, 100, 255), -1)

    failsafe_active = (not left_found) and (not right_found)

    # ── Activation reset ──────────────────────────────────────
    # If both hands leave the frame, drop out of the activated state so the
    # gate must be re-armed (both hands re-centered) before live values flow.
    if failsafe_active:
        activated = False

    if failsafe_active:
        # Both hands lost: bleed throttle down from its current value toward
        # minimum (a soft "ease down" rather than an instant drop), and snap
        # the attitude channels to neutral so the craft doesn't tumble.
        smooth_throttle = max(CH_MIN, smooth_throttle - THROTTLE_DECAY)
        smooth_yaw      = CH_MID
        smooth_pitch    = CH_MID
        smooth_roll     = CH_MID
    else:
        # Normal operation: exponential smoothing on all channels.
        smooth_throttle = ALPHA * throttle + (1 - ALPHA) * smooth_throttle
        smooth_yaw      = ALPHA * yaw      + (1 - ALPHA) * smooth_yaw
        smooth_pitch    = ALPHA * pitch    + (1 - ALPHA) * smooth_pitch
        smooth_roll     = ALPHA * roll     + (1 - ALPHA) * smooth_roll

    # ── Activation gate ───────────────────────────────────────
    # Latch 'activated' the first time BOTH hands are centered together.
    if (not activated) and left_centered and right_centered:
        activated = True

    if activated:
        out_throttle = smooth_throttle
        out_yaw      = smooth_yaw
        out_pitch    = smooth_pitch
        out_roll     = smooth_roll
    else:
        # Not yet activated: hold safe neutral (throttle zero, attitude center).
        # Also keep the smoothed values parked so there's no jump at activation.
        smooth_throttle = CH_MIN
        smooth_yaw      = CH_MID
        smooth_pitch    = CH_MID
        smooth_roll     = CH_MID
        out_throttle = CH_MIN
        out_yaw      = CH_MID
        out_pitch    = CH_MID
        out_roll     = CH_MID

    fpga.send(throttle=out_throttle,
             yaw=out_yaw,
             pitch=out_pitch,
             roll=out_roll)

    # ── Neutral center dots ───────────────────────────────────
    # Draw a target dot at each hand's neutral (center) point. When the
    # palm is inside the ring, that hand is in the neutral deadzone
    # (throttle zero / attitude centered) and the dot turns green.
    def draw_center_dot(img, dot, centered):
        cx, cy = dot
        if centered:
            cv2.circle(img, (cx, cy), 6, (0, 255, 0), -1)
            cv2.circle(img, (cx, cy), CENTER_SNAP_PX, (0, 255, 0), 2)
        else:
            cv2.circle(img, (cx, cy), 6, (255, 255, 255), -1)
            cv2.circle(img, (cx, cy), CENTER_SNAP_PX, (180, 180, 180), 1)
        cv2.line(img, (cx - 10, cy), (cx + 10, cy), (255, 255, 255), 1)
        cv2.line(img, (cx, cy - 10), (cx, cy + 10), (255, 255, 255), 1)

    draw_center_dot(frame, left_dot,  left_centered)
    draw_center_dot(frame, right_dot, right_centered)

    # ── Debug HUD ─────────────────────────────────────────────
    def draw_bar(img, label, value, y_pos, color):
        bar_len = int((value - CH_MIN) / 1000 * 200)
        cv2.putText(img, f"{label}: {int(value)}", (10, y_pos - 5),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 1)
        cv2.rectangle(img, (10, y_pos), (10 + bar_len, y_pos + 10), color, -1)
        cv2.rectangle(img, (10, y_pos), (210, y_pos + 10), (200, 200, 200), 1)
        # center tick (1500)
        cx = 10 + 100
        cv2.line(img, (cx, y_pos - 2), (cx, y_pos + 12), (255, 255, 255), 1)

    draw_bar(frame, "THR", smooth_throttle, 30,  (255, 100, 0))
    draw_bar(frame, "YAW", smooth_yaw,      60,  (255, 100, 0))
    draw_bar(frame, "PIT", smooth_pitch,    90,  (0, 100, 255))
    draw_bar(frame, "ROL", smooth_roll,     120, (0, 100, 255))

    cv2.putText(frame, f"L:{'OK' if left_found else 'X'}  R:{'OK' if right_found else 'X'}",
                (10, 150), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)

    if not activated:
        cv2.putText(frame, "CENTER BOTH HANDS TO ACTIVATE", (10, 210),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 200, 255), 2)
    else:
        cv2.putText(frame, "ACTIVE", (10, 210),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)

    if failsafe_active:
        cv2.putText(frame, "FAILSAFE - THROTTLE DECAY", (10, 180),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)

    # ── Active-region guides ──────────────────────────────────
    cv2.line(frame, (0, int(V_MIN * h)), (w, int(V_MIN * h)), (80, 80, 80), 1)
    cv2.line(frame, (0, int(V_MAX * h)), (w, int(V_MAX * h)), (80, 80, 80), 1)
    cv2.line(frame, (w // 2, 0), (w // 2, h), (80, 80, 80), 1)
    # Midline marking the throttle "zero below / scale above" boundary
    cv2.line(frame, (0, int(V_CENTER * h)), (w, int(V_CENTER * h)), (60, 120, 60), 1)

    cv2.imshow("Gesture Control", frame)
    if cv2.waitKey(5) & 0xFF == 27:
        break

cap.release()
cv2.destroyAllWindows()
landmarker.close()
fpga.close()