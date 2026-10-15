# AirSwipe

Change pages and scroll on your Mac by moving your hand in the air. It uses only
the built-in camera and Apple's Vision framework, and everything runs on-device.

| You do | It does |
|---|---|
| Hold an open palm still for ~0.5 s | **Arms** it (menu-bar icon shows `ON`) |
| Swipe your hand right / left | **Back** / **Forward** (`Cmd+[` / `Cmd+]`) |
| Raise / lower your hand from where you armed it | **Scroll** up / down, faster the farther you go |
| Make a fist, or lower your hand out of view | **Disarms** it |

Nothing fires unless it is armed, which is what stops waving at someone from
changing your page.

## Status

- **Gesture logic** (`AirSwipeCore`): built test-first, 35 passing tests.
- **Camera, Vision, event posting, menu bar** (`airswipe`): builds cleanly, but
  has **not** been run against a real camera yet. See *First run* below.

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

Start with the dry run. Hold your palm up, wait for `armed`, then swipe and raise
or lower your hand and watch the messages. If a direction feels wrong, fix it
with a flag below before using `--live`.

## Test checklist (about 3 minutes)

1. In **Terminal.app**, `cd` into this folder and run `swift run airswipe`
   (the first build takes a few seconds).
2. Click **Allow** on the camera prompt. If you missed it, enable your terminal app
   under System Settings > Privacy & Security > Camera and run it again.
3. Hold an open palm still in front of the camera.
   Expect `armed: hand gestures are on`, and the menu-bar icon changes to `🖐 ON`.
4. Swipe your hand to **your right**. Expect `swipe right`, then `would go BACK`.
   Swipe to your left: `swipe left`, then `would go FORWARD`.
5. Raise your hand a palm's width above where you armed it. Expect
   `would scroll UP` lines. Lower it for `DOWN`. At the start height: nothing.
6. Hold a fist for about half a second. Expect `disarmed`.
   (A quick closing during a swipe is deliberately ignored.)
7. If a direction is wrong, see *If it feels wrong* below. Only when the dry run
   behaves, try `swift run airswipe --live` with a browser open on a page that has
   history.

## Options

| Flag | Effect |
|---|---|
| *(none)* | Dry run |
| `--live` | Post real key and scroll events |
| `--desktops` | Swipes switch desktops (`Ctrl+←/→`) instead of back/forward |
| `--invert-scroll` | Flip the scroll direction |
| `--no-mirror` | Do not mirror the camera horizontally |
| `--debug` | Print what the camera layer sees about ten times a second (hand found, per-finger reach ratios and confidences, palm position, armed state) |

## If it feels wrong

| Symptom | Try |
|---|---|
| Swipe right goes forward instead of back | `--no-mirror` |
| Raising your hand scrolls the wrong way | `--invert-scroll` |
| It never arms | Hold the palm flatter and still, face the camera, add light |
| It arms when you did not mean it | Raise `armHoldDuration` in `GestureConfig` |
| Swipes are missed | Lower `swipeMinDistance` or `swipeMaxVerticalRatio` |
| Scroll creeps with your hand at rest | Raise `scrollDeadZone` |

Every threshold is a field of `GestureConfig` in
`Sources/AirSwipeCore/Types.swift`, with times in seconds and distances as a
fraction of the camera frame.

## How it works

```
CameraSource ─frames→ HandTracker ─HandSample?→ GestureEngine ─GestureEvent→ ActionMapper ─Action→ ActionSink
 (AVFoundation)        (Vision)                 (pure state machine)          (pure)               (CGEvent / console)
```

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
- "Open palm" is a geometric guess from finger joints and may need tuning for
  your hands and lighting (`extensionRatio` in `OpenPalmClassifier`).
- It sends keyboard shortcuts, not true trackpad gestures, so it works in apps
  that honor `Cmd+[` / `Cmd+]`.
- Not packaged as an `.app`, not signed or notarized.
