# AirSwipe — Design Spec

**Date:** 2026-10-15 · **Status:** approved in chat

## Goal

Navigate pages and scroll on a Mac by moving a hand in the air, using only the
built-in camera: the trackpad's swipe and scroll, without touching it.

## Gestures

| Gesture | Effect |
|---|---|
| Open palm held still ≈0.5 s | **Start.** Arms the app. The menu-bar icon changes. |
| One finger (index), fast horizontal move | Hand moves right → Back (`Cmd+[`). Hand moves left → Forward (`Cmd+]`). `--desktops` maps to `ctrl+←/→` instead. |
| Two fingers (index and middle), hand moving up or down | Scrolls up or down: the page follows the hand and stops when it does. `--rate-scroll` restores the earlier model where height above or below the pose's start sets speed. |
| Fist held ≥0.5 s, hand out of frame ≥1 s, or ~15 s with no gesture | **Stop.** Disarms. Re-arm by holding an open palm again. |

The number of fingers is the command. A pose only becomes the mode once it has
been steady for 0.15 s, an in-between pose does nothing and never disarms, and
position is tracked in every pose so a swipe survives a flicker. This replaced an
earlier open-hand model after a real-camera log showed that fast swipes make the
open/closed reading dip below threshold for ~0.2 s, and that a natural two-finger
scroll was being read as a fist.

A **return guard** keeps the hand's return stroke from swiping back: after a
swipe, further swipes are held off until the hand has settled near the swipe's
origin (0.15 s), rested anywhere for 1.5 s, or 3 s have passed. The motion still
sitting in the swipe window is discarded when the guard lifts. This was found
with a real-camera report ("returning to the middle moves the other way") and an
instrumented test showing the blocked return firing the instant the guard lifted.

Nothing fires unless armed. That single rule is what stops waving at someone
from changing the page.

## Decisions

1. **Arm first.** A deliberate, still open palm is cheap to detect and rare by accident.
2. **Scroll is rate control, not position control.** Hand height relative to the
   arming height sets scroll *speed*. It needs no finger-level detail and has no
   range limit. Pinch-and-drag may replace it later behind the same interface.
3. **Dry run by default.** The binary prints what it *would* do. `--live` posts
   real key and scroll events. Camera permission is needed either way;
   Accessibility permission only for `--live`.
4. **Page-turn metaphor for direction.** Right-to-left motion advances (forward),
   left-to-right goes back, matching how a trackpad swipe moves page content.
   One config switch flips it.
5. **Decision logic is pure.** `GestureEngine` takes timestamped samples and returns
   events. It has no camera, Vision or AppKit dependency, so the hard part
   (false positives) is unit-testable with synthetic hand paths.

## Architecture

```
CameraSource ─frames→ HandTracker ─HandSample?→ GestureEngine ─GestureEvent→ ActionMapper ─Action→ ActionSink
 (AVFoundation)        (Vision)                 (pure state machine)          (pure)               (CGEvent / console)
```

- **AirSwipeCore** (library, tested): `HandSample`, `GestureEvent`, `GestureConfig`,
  `GestureEngine`, `ActionMapper`, `OpenPalmClassifier`.
- **airswipe** (executable, built but hardware-verified by hand): `CameraSource`,
  `HandTracker`, `ConsoleSink`, `CGEventSink`, `StatusItemController`, CLI parsing.

## Non-goals (v1)

Custom gesture training, a settings UI, two-hand input, an `.app` bundle,
signing or notarization, smoothing filters.

## Unverified assumptions (need a real camera to confirm)

- The camera frame is not mirrored, so x is flipped to the user's point of view.
- Positive `CGEvent` scroll-wheel delta scrolls toward the top of the page
  (`--invert-scroll` flips it).
- A bare binary launched from Terminal gets camera permission attributed to Terminal.
- The finger-straightness thresholds (extended ≥0.92, curled ≤0.88) come from one
  hand with the wrist in view: extended fingers measured 0.98 to 1.00 and nothing
  that was not extended measured above 0.86. They replaced wrist-relative reach
  ratios, which turned to noise when the hand sat at the bottom edge of the frame
  (49% of frames read as no pose). Straightness uses no wrist, so it should hold
  there, but that still needs confirming on a camera with the hand held low, and
  other hands and lighting may need tuning.
