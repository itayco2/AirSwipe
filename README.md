# AirSwipe

Change pages and scroll on your Mac by moving your hand in the air. It uses only
the built-in camera and Apple's Vision framework, and everything runs on-device.

**The number of fingers is the command.**

| You show | It does |
|---|---|
| ✋ Open palm, held still ~0.5 s | **Start.** Menu-bar icon shows `ON` |
| ☝️ One finger, move right / left | **Swipe:** Back / Forward (`Cmd+[` / `Cmd+]`) |
| ✌️ Two fingers, raise / lower your hand | **Scroll** up / down, faster the farther you go |
| ✊ Fist, held ~0.5 s (or hand out of view) | **Stop** |

The pose decides what a movement means, so gestures can't be confused: sideways
motion only swipes in the one-finger pose, and height only scrolls in the
two-finger pose. A pose has to be steady for a moment before it counts, so a
flicker between poses can't switch modes. Scroll speed is measured from where you
first showed two fingers.

**The return stroke never swipes.** After a swipe, further swipes wait until your
hand settles back near where that swipe started (the middle). The guard also
lifts if you rest anywhere for about 1.5 s, or after 3 s, so it can't get stuck.

## Status

- **Gesture logic** (`AirSwipeCore`): built test-first, 51 passing tests.
- **Camera layer** (`airswipe`): run on a real camera once. Tracking, arming,
  swipe right, fist and hand-out-of-view worked in a debug log. The finger-count
  thresholds were derived from that log (open palm, two fingers, fist); the
  **one-finger pose has not been seen on a real hand yet**, so expect to tune.

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

Start with the dry run and watch the messages before using `--live`.

## Test checklist (about 3 minutes)

1. In **Terminal.app**, `cd` into this folder and run `swift run airswipe`.
2. Click **Allow** on the camera prompt.
3. Hold a flat open palm still. Expect `armed: hand gestures are on`.
4. Show **one finger** (index up, other fingers curled), pause a beat, then swipe
   to **your right**. Expect `swipe right`, then `would go BACK`. Bring your hand
   back to the middle: **nothing should fire**. Then swipe left: `swipe left`,
   then `would go FORWARD`.
5. Show **two fingers** (index and middle up). Raise your hand: `would scroll UP`.
   Lower it: `would scroll DOWN`.
6. Go back to an open palm and move around. Nothing should happen.
7. Make a fist for about half a second. Expect `disarmed`.
8. If something is off, run with `--debug` and look at the `pose=` field: it
   should read `openPalm`, `oneFinger`, `twoFingers` or `fist` for the pose you
   are showing.

## Options

| Flag | Effect |
|---|---|
| *(none)* | Dry run |
| `--live` | Post real key and scroll events |
| `--desktops` | Swipes switch desktops (`Ctrl+←/→`) instead of back/forward |
| `--invert-scroll` | Flip the scroll direction |
| `--no-mirror` | Do not mirror the camera horizontally |
| `--debug` | Print what the camera layer sees about ten times a second (hand found, per-finger reach ratios, pose, palm position, armed state) |

## If it feels wrong

| Symptom | Try |
|---|---|
| Swipe right goes forward instead of back | `--no-mirror` |
| Raising your hand scrolls the wrong way | `--invert-scroll` |
| It never arms | Hold the palm flat and still, face the camera, add light |
| One or two fingers are not recognized | `--debug`: the extended fingers should show a ratio of about 1.5 or more and the curled ones about 1.1 or less. Curl the other fingers tighter, or tune `extendedRatio` / `curledRatio` in `HandPoseClassifier` |
| It switches modes too slowly or too eagerly | `poseStableDuration` in `GestureConfig` |
| Swipes are missed | Lower `swipeMinDistance` or `swipeMaxVerticalRatio` |
| A swipe is ignored right after another one | The return guard is waiting for your hand to come back to the middle. Return there, or rest about 1.5 s. Tune `swipeReturnGuard` and `swipeHomeRadius` |
| Scroll creeps with your hand at rest | Raise `scrollDeadZone` |

Every threshold is a field of `GestureConfig` in
`Sources/AirSwipeCore/Types.swift`, with times in seconds and distances as a
fraction of the camera frame.

## How it works

```
CameraSource ─frames→ HandTracker ─HandSample?→ GestureEngine ─GestureEvent→ ActionMapper ─Action→ ActionSink
 (AVFoundation)        (Vision + pose)          (pure state machine)          (pure)               (CGEvent / console)
```

`HandTracker` turns the 21 Vision joints into a position and a `HandPose`. The
engine takes timestamped samples and returns events. It has no camera or clock,
so false positives can be tested with synthetic hand paths:

```bash
swift test
```

Design and plan: [`docs/superpowers/specs`](docs/superpowers/specs/2026-10-15-airswipe-design.md),
[`docs/superpowers/plans`](docs/superpowers/plans/2026-10-15-airswipe.md).

## Known limits

- One hand, one camera, and it needs reasonable light.
- Hand pose runs continuously while the app is open, which costs CPU and battery.
- Poses come from the reach of each finger past its knuckle, so they are a
  geometric guess that may need tuning for your hands and lighting. The thumb is
  ignored.
- It sends keyboard shortcuts, not true trackpad gestures, so it works in apps
  that honor `Cmd+[` / `Cmd+]`.
- Not packaged as an `.app`, not signed or notarized.
