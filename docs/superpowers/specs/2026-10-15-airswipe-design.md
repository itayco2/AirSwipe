# AirSwipe — Design Spec

**Date:** 2026-10-15 · **Status:** approved in chat

## Goal

Navigate pages and scroll on a Mac by moving a hand in the air, using only the
built-in camera: the trackpad's swipe and scroll, without touching it.

## Gestures

| Gesture | Effect |
|---|---|
| Open palm held still ≈0.5 s | **Arms** the app. The menu-bar icon changes. |
| Fast horizontal swipe (armed) | Hand moves right → Back (`Cmd+[`). Hand moves left → Forward (`Cmd+]`). `--desktops` maps to `ctrl+←/→` instead. |
| Hand above or below the arming height (armed) | Scrolls up or down. Speed grows with distance, with a dead zone around neutral. |
| Fist ≥0.2 s, hand out of frame ≥1 s, or ~6 s with no gesture | **Disarms.** Re-arm by holding an open palm again (this also resets the neutral height). |

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
- The open-palm geometry thresholds work for real hands and lighting.
