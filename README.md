# AirSwipe

Change pages and scroll on your Mac by moving your hand in the air. It uses only
the built-in camera and Apple's Vision framework, and everything runs on-device.

**The number of fingers is the command.**

| You show | It does |
|---|---|
| ✋ Open palm, held still ~0.5 s | **Start.** Menu-bar icon shows `ON` |
| ☝️ One finger, move right / left | **Swipe:** Back / Forward (`Cmd+[` / `Cmd+]`) |
| ✌️ Two fingers, move your hand up / down | **Scroll:** the page follows your hand |
| ✊ Fist, held ~0.5 s (or hand out of view) | **Stop** |

The pose decides what a movement means, so gestures can't be confused: sideways
motion only swipes in the one-finger pose, and up/down motion only scrolls in the
two-finger pose. A pose has to be steady for a moment before it counts, so a
flicker between poses can't switch modes.

**Scrolling follows your hand,** like two fingers on a trackpad: move up and the
page scrolls up, move down and it scrolls down, hold still and it stops. To go
farther than your arm reaches, switch to an open palm, reposition, and show two
fingers again. (`--rate-scroll` restores the older model where hand height sets
the speed.)

**The return stroke never swipes.** After a swipe, further swipes wait until your
hand is back at the middle and has turned around or slowed. Your hand can come
back and go straight into the next swipe with no pause. The guard also lifts if
you rest anywhere for about 1.5 s, or after 3 s, so it can't get stuck.

**It works with your hand held low.** Poses come from how *straight* each finger
is, which needs only the finger's own joints. The wrist, which is out of view when
a hand rests above the keyboard, isn't used, and neither is the size or angle of
the hand.

## Status

- **Gesture logic** (`AirSwipeCore`): built test-first, 70 passing tests.
- **Camera layer** (`airswipe`): run on a real camera over several sessions, and
  the thresholds were set from those logs. Finger straightness was calibrated
  with the wrist in view. Behavior with the hand at the very bottom edge of the
  frame should be confirmed on a camera. Treat feel (scroll gain, swipe distance)
  as still tunable.

## Requirements

- macOS 13 or later, Apple Silicon or Intel
- Swift 5.9+ (the Xcode Command Line Tools are enough; Xcode.app is not needed)

## First run

```bash
swift run airswipe            # dry run: prints what it would do, posts nothing
swift run airswipe --live     # really posts back/forward and scroll events
```

Run it from Terminal.app or iTerm. macOS will ask for **Camera** access for that
terminal app. `--live` also needs **Accessibility** access for the same app
(System Settings > Privacy & Security > Accessibility); without it macOS drops
the events silently.

Start with the dry run and watch the messages before using `--live`. In live mode
keep a browser in front: `Cmd+[` and `Cmd+]` are indent and outdent in many code
editors.

## Test checklist (about 3 minutes)

1. In **Terminal.app**, `cd` into this folder and run `swift run airswipe`.
2. Click **Allow** on the camera prompt.
3. Hold a flat open palm still. Expect `armed: hand gestures are on`.
4. Show **one finger** (index up, other fingers curled), pause a beat, then swipe
   to **your right**. Expect `swipe right`, then `would go BACK`. Bring your hand
   back to the middle: **nothing should fire**. Then swipe left: `swipe left`,
   then `would go FORWARD`.
5. Show **two fingers** (index and middle up). Move your hand **up** a little:
   `would scroll UP`. Move it **down**: `would scroll DOWN`. Hold still: nothing.
6. Go back to an open palm and move around. Nothing should happen.
7. Make a fist for about half a second. Expect `disarmed (fist held)`.
8. If something is off, run with `--debug` and look at `mode=` and `pose=`: they
   should read `oneFinger` / `twoFingers` for the pose you are showing.

## Options

| Flag | Effect |
|---|---|
| *(none)* | Dry run |
| `--live` | Post real key and scroll events |
| `--desktops` | Swipes switch desktops (`Ctrl+←/→`) instead of back/forward |
| `--invert-scroll` | Flip the scroll direction |
| `--rate-scroll` | Scroll by hand height (speed) instead of following the hand |
| `--no-mirror` | Do not mirror the camera horizontally |
| `--debug` | Print what the camera layer sees about ten times a second (engine mode and return-guard state, hand found, per-finger straightness, pose, knuckle position, armed state) |

## If it feels wrong

| Symptom | Try |
|---|---|
| Swipe right goes forward instead of back | `--no-mirror` |
| Raising your hand scrolls the wrong way | `--invert-scroll` |
| It never arms | Hold the palm flat and still, face the camera, add light |
| One or two fingers are not recognized | `--debug`: `str=` is each finger's straightness. Extended fingers read about 0.98 to 1.00 and curled ones 0.9 or less. Curl the other fingers tighter, or tune `extendedStraightness` / `curledStraightness` in `HandPoseClassifier` |
| It switches modes too slowly or too eagerly | `poseStableDuration` in `GestureConfig` |
| Swipes are missed | Lower `swipeMinDistance` (default 0.12 of the frame) or raise `swipeWindow` |
| A swipe is ignored right after another one | The return guard is waiting for your hand to come back to the middle. Return there, or rest about 1.5 s. Tune `swipeReturnGuard` and `swipeHomeRadius` |
| Scroll is too fast or too slow | `scrollFollowGain` (default 2.5) |
| Scroll jitters with your hand at rest | Raise `scrollFollowDeadband` or lower `scrollSmoothing` |

Every threshold is a field of `GestureConfig` in
`Sources/AirSwipeCore/Types.swift`, with times in seconds and distances as a
fraction of the camera frame.

## How it works

```
CameraSource ─frames→ HandTracker ─HandSample?→ GestureEngine ─GestureEvent→ ActionMapper ─Action→ ActionSink
 (AVFoundation)        (Vision + pose)          (pure state machine)          (pure)               (CGEvent / console)
```

`HandTracker` turns the Vision joints into a knuckle position and a `HandPose`.
The engine takes timestamped samples and returns events. It has no camera or
clock, so false positives can be tested with synthetic hand paths:

```bash
swift test
```

Design and plan: [`docs/superpowers/specs`](docs/superpowers/specs/2026-10-15-airswipe-design.md),
[`docs/superpowers/plans`](docs/superpowers/plans/2026-10-15-airswipe.md).

## Known limits

- One hand, one camera, and it needs reasonable light.
- Hand pose runs continuously while the app is open, which costs CPU and battery.
- Poses come from finger straightness, a geometric measure that may need tuning
  for your hands and lighting. The thumb is ignored.
- Your fingers and knuckles have to stay inside the picture. If the hand leaves
  the frame for about a second it stops (`disarmed (hand out of view)`).
- It sends keyboard shortcuts, not true trackpad gestures, so it works in apps
  that honor `Cmd+[` / `Cmd+]`.
- Not packaged as an `.app`, not signed or notarized.
