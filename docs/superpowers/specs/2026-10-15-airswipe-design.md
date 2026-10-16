# AirSwipe — Design Spec

**Date:** 2026-10-15 · **Status:** approved in chat

## Goal

Navigate pages and scroll on a Mac by moving a hand in the air, using only the
built-in camera: the trackpad's swipe and scroll, without touching it.

## Gestures

| Gesture | Effect |
|---|---|
| Open palm held still ≈0.5 s | **Start.** Arms the app. The menu-bar icon changes. |
| One finger (index), fast horizontal move | **Switches screens**, like the trackpad's 3- or 4-finger swipe between full-screen apps and desktops: hand moves right → screen on the left (`ctrl+←`), hand moves left → screen on the right (`ctrl+→`). `--history` maps to browser back/forward (`Cmd+[` / `Cmd+]`) instead. |
| One finger (index), fast vertical move | **Flick:** scrolls, and the page then follows the hand for as long as it keeps going that way (`flickScrollGain`, default 2.0 full-speed-seconds per frame height), so the distance scrolled is the distance the hand moved. Up moves toward the top of the page. The move back scrolls nothing. A diagonal move is neither a swipe nor a flick. |
| Two fingers (index and middle), hand moving up or down | **Fine scroll:** the page follows the hand and stops when it does. `--rate-scroll` restores the earlier model where height above or below the pose's start sets speed. |
| Fist held still ≥0.5 s, hand out of frame ≥1 s, or ~15 s with no gesture | **Stop.** Disarms. Re-arm by holding an open palm again. A fist that is moving (more than `fistStillnessRadius`, 0.06) does not count. |

The number of fingers is the command. A pose only becomes the mode once it has
been steady for 0.15 s, an in-between pose does nothing and never disarms, and
position is tracked in every pose so a swipe survives a flicker. This replaced an
earlier open-hand model after a real-camera log showed that fast swipes make the
open/closed reading dip below threshold for ~0.2 s, and that a natural two-finger
scroll was being read as a fist.

**Unclear poses do not end stroke mode.** A real-camera run with `--debug` showed
flicks down never registering while flicks up did. With the hand low in the frame
the pose read as `other` or `fist` for most of 10 s (46 of 64 readings), the engine
dropped out of one-finger mode, and 45 moves of up to 0.25 of the frame, two to
three times the threshold, were refused for that reason alone. Worse, when the pose
recovered, the hand's move back up counted as a flick up, which is how "one down
and eight ups" came about. Two changes followed, both found by replaying the log
through the engine: readings of `other` or `fist` leave one-finger mode alone
(`strokePoseHold`, 1 s, ends it if no one-finger reading comes), and the little
finger no longer decides between one finger and two, since a little finger that
read as extended caused 13 of the 41 unclear frames. Replaying the same log, the
engine went from 4 flicks up and none down to a plausible mix of both.

**Up and down have no carry-on, and a flick scrolls with the hand.** Live use
reported three things: a return to the middle sometimes fired another flick, the
scroll was a fixed jump rather than "actual scroll", and the app sometimes
disarmed because a moving hand looked closed. Replaying the recorded log showed
returns overshooting the middle by 0.03 to 0.07, right under the 0.08 that
counted as a deliberate "carry on" the other way, so the exception was removed
for up and down (sideways keeps it, since it works): the way back is ignored
however far it goes. The fixed 80%-of-a-screen jump was replaced by following the
hand: the flick scrolls the distance already covered at once, then keeps scrolling
by how much farther the hand goes the same way, and ends once the hand backs off
more than `flickFollowReversal` (0.015). The stop gesture now needs the fist held
still, as arming needs the palm held still.

**Flicks start from a rest (2026-10-16).** A debug capture showed up and down still
mixing three ways: the return dipped below its start height and the rebound fired a
flick (the position-based guard lifted at the trough), pose flicker shifted the hand's
reading by 0.04 to 0.05 so a resting hand seemed to move 0.08 to 0.11, and repeated
flicks down ended at the bottom edge where the dip's return fired a flick up. All
three are moves that do not start from a rest, so the vertical return guard was
replaced by `RestTracker`: a flick needs the hand within `flickRestRadius` (0.02) of
one spot for `flickRestDuration` (0.2 s), and then `flickMinDistance` (0.08) of travel
away from *that spot* within `flickMoveWindow` (0.8 s of leaving it; the first live
capture showed deliberate sweeps starting slowly and taking 0.6 to 0.8 s to cover 0.08,
which the first value of 0.25 s rejected, so drifts slower than about 0.06 of the frame
per second are what is ignored). A move turned down as the way back stays turned down
until the hand rests again, so a slow return cannot become a flick once the delay runs out. Measuring from the rest rather than as the swing
between the highest and lowest point in the window halves the apparent size of a
symmetric pose-flicker shift. After a flick the opposite direction is ignored for
`flickReverseDelay` (0.8 s), because pausing at the end of a flick and coming back is
the way back; the same direction is not held, so several flicks down in a row work
with a pause between. Vertical flicks no longer wait for, or set, the sideways return
guard. A first idea, ignoring unclear-pose frames in the vertical signal, was dropped
because it would lose real flicks: with the hand low in the frame most readings are
unclear. Numbers are starting values, to be tuned from a live capture; a pose
flicker that happens right after the hand has rested in the *other* pose class can
still look like a flick.

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
