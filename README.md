# AirSwipe

Control your Mac by moving your hand in the air: switch screens, scroll like on a
phone, and drive voice dictation, using only the built-in camera. Hand tracking is
Apple's Vision framework, everything runs on-device, and no frame is ever stored.

Written in Swift for macOS. No dependencies beyond Apple's frameworks, and the
Xcode Command Line Tools are enough to build it.

## What it does

| You show | It does |
|---|---|
| ✋ Open palm, held still ~0.5 s | **Start.** The menu-bar icon shows `ON` |
| 🤏 **Pinch** (thumb and index fingertip touching), move your hand up / down | **Scroll like on a phone:** the page follows your hand while you pinch; open the pinch to let go |
| ☝️ One finger, move **right / left** | **Switch screen**, like a 3- or 4-finger trackpad swipe between full-screen apps and desktops (`Ctrl+←/→`) |
| ✌️ Two fingers, move your hand up / down | **Fine scroll:** the page follows your hand |
| ✊ Fist, held still ~0.5 s (or hand out of view) | **Stop** |
| ✋ Open palm, draw a **circle** *(with `--voice`)* | **Start / stop voice dictation** in the Claude message box |
| 👍 Thumbs up, held still ~0.7 s *(with `--voice`)* | **Send the message** (stops dictation first if it is running) |

Nothing fires unless the engine is armed, which is what stops waving at someone from
changing the page.

## Design notes

The interesting part of this project is deciding what a hand is *doing* from a noisy
20 fps camera feed, and every choice below comes from recordings of a real hand.

- **A pure state machine.** `GestureEngine` takes timestamped hand samples and returns
  events. It never reads a clock or touches the camera, so false positives, the hard
  part of gesture control, are tested with synthetic hand paths (171 tests,
  Swift Testing) and by replaying recorded camera logs.
- **Poses from finger straightness.** A finger is extended or curled by how straight
  its own joints are, which needs no wrist (out of view when a hand rests above a
  keyboard), hand size or angle.
- **The pinch is the clutch for scrolling.** An earlier up/down "flick" gesture kept
  mixing up its direction, because in the air there is no finger lift: every move back
  looked like a new flick. Recordings also showed one finger was read as one finger in
  only 52 to 66% of frames while the hand moved (80 to 87% still). So scrolling now
  uses the distance between thumb tip and index tip, as a share of knuckle width. It
  read 0.01 to 0.17 through whole pinched drags and 1.3 or more with the hand open,
  whatever the other fingers looked like. Opening the pinch is lifting the finger, so
  the way back scrolls nothing. While a pinch is on, it outranks every pose (a pinch
  with curled fingers reads as a fist or a thumbs up).
- **Thresholds measured, not guessed.** A thumbs up was first confused with a relaxed
  fist; the recordings showed the fingers separated them (tightly curled in a real
  thumbs up, looser in a fist), so that is what the classifier checks.
- **Voice without audio code.** AirSwipe records nothing. It presses the macOS
  Dictation shortcut as a realistic keyboard event (modifiers as their own events, the
  key held ~100 ms; a bare key-down/up starts Dictation but cannot stop it). The Claude
  desktop app is built on Chromium, so a start circle asks it to build its
  accessibility tree and focuses the message box through the macOS accessibility API,
  with no click needed.
- **Safe by default.** It is a dry run that posts nothing until you pass `--live`, and
  voice features are off until you pass `--voice`.

## Requirements

- macOS 13 or later, Apple Silicon or Intel
- Swift 5.9+ (the Xcode Command Line Tools are enough; Xcode.app is not needed)
- For switching screens: *Move left/right a space* turned on under System Settings >
  Keyboard > Keyboard Shortcuts > Mission Control (it is on by default)

## Run it

```bash
swift run airswipe            # dry run: prints what it would do, posts nothing
swift run airswipe --live     # really posts screen-switch and scroll events
```

Run it from Terminal.app or iTerm. macOS will ask for **Camera** access for that
terminal app. `--live` also needs **Accessibility** access for the same app (System
Settings > Privacy & Security > Accessibility); without it macOS drops the events
silently. Start with the dry run and watch the messages before using `--live`.
Scrolling goes to whatever is under the mouse pointer, so rest it over the page.

### Try it (about 3 minutes)

1. Run `swift run airswipe` and click **Allow** on the camera prompt.
2. Hold a flat open palm still. Expect `armed: hand gestures are on`.
3. Show **one finger** (index up, others curled), pause a beat, then swipe to **your
   right**. Expect `swipe right`. Bring your hand back: nothing should fire. Swipe left.
4. **Pinch** your thumb and index fingertip together and move your hand up and down:
   the page should follow. Open the pinch, move back, pinch again.
5. Optional: show **two fingers** and move up and down for fine scroll.
6. Hold a fist **still** for half a second. Expect `disarmed (fist held)`.
7. If something is off, add `--debug` and look at `pose=` and `pinch=`.

### Voice dictation (`--voice`)

One-time setup:

1. System Settings > Keyboard > Dictation: turn Dictation on.
2. Set its **Shortcut** to **Customize…** and press **Control + Option + D** (any other
   chord works if you pass the same one as `--voice-key`).
3. Run `swift run airswipe --live --voice` from a shell that has Accessibility
   permission and give it about 6 seconds, so the Claude app can build its interface.

Then: draw a circle with an open palm, talk, then give a thumbs up. The circle focuses
the Claude message box and starts dictation; the thumbs up stops it, waits for the text
to land, and presses Return. A second circle instead of the thumbs up stops dictation
without sending. `--voice-target frontmost` presses the key into whatever is focused
(for a terminal), and `airswipe --focus-claude` tests the focusing step alone.

## Options

| Flag | Effect |
|---|---|
| *(none)* | Dry run |
| `--live` | Post real key and scroll events |
| `--voice` | Palm circle starts/stops dictation, thumbs up sends |
| `--voice-key CHORD` | The chord to press, like `ctrl+opt+d` or `meta+k`. Implies `--voice` |
| `--voice-target claude\|frontmost` | `claude` (default): focus the Claude message box first. `frontmost`: press the key into whatever is focused |
| `--focus-claude` | Focus the Claude message box once and exit, to test that step alone |
| `--history` | Swipes go back/forward inside an app (`Cmd+[` / `Cmd+]`) instead of switching screens |
| `--invert-scroll` | Flip the scroll direction (pinch and fine scroll) |
| `--rate-scroll` | Fine scroll by hand height (speed) instead of following the hand |
| `--no-mirror` | Do not mirror the camera horizontally |
| `--debug` | Print what the camera layer sees about ten times a second: engine mode, `grab=` (page held by a pinch), per-finger straightness, pose, thumb, `pinch=distance/confidence`, knuckle position. A move that was big enough to be a swipe but was turned down ends the line with `REJECTED` and the reason |

## If it feels wrong

Every threshold is a field of `GestureConfig` in `Sources/AirSwipeCore/Types.swift`
(times in seconds, distances as a share of the camera frame).

| Symptom | Try |
|---|---|
| Swipe right moves to the wrong side | `--no-mirror` |
| Swiping does nothing to Chrome or another app | They must be on different screens (full-screen apps or desktops); check *Move left/right a space* in Mission Control shortcuts |
| The page scrolls the wrong way, or too far | `--invert-scroll`, or `pinchScrollGain` (3.0) / `scrollFollowGain` (2.5) |
| The pinch does not grab | `--debug`: `pinch=` should read 0.18 or less while the fingertips touch (`pinchEngageRatio`) for 0.1 s, with confidence 0.6 or more after the slash. Face the thumb tip and index tip at the camera and keep the hand off the bottom edge |
| The pinch will not let go, or scrolling stutters | It lets go at 0.35 or more for 0.15 s; between 0.18 and 0.35 nothing changes, on purpose |
| A fist scrolls instead of stopping | The fist read as a pinch (a real fist read 0.24 to 0.74). Lower `pinchEngageRatio` |
| It stops when you did not mean to | A fist must be held still: `fistStillnessRadius` (0.06) and `fistDisarmDuration` (0.5 s) |
| It never arms | Hold the palm flat and still, face the camera, add light |
| Swipes are missed | Lower `swipeMinDistance` (0.12) or raise `swipeWindow`. Diagonal moves are ignored: `swipeMaxVerticalRatio` |
| A swipe is ignored right after another | The return guard waits for your hand to come back to where the swipe started; rest about 1.5 s, or tune `swipeReturnGuard` / `swipeHomeRadius` |
| One or two fingers are not recognized | `--debug`: `str=` is each finger's straightness (extended ≈ 0.98 to 1.00, curled ≤ 0.9). Curl the others tighter, or tune `extendedStraightness` / `curledStraightness` |
| The circle does nothing | Arm first, use an open palm, draw one loop that closes within 2 s and spans at least 0.10 of the picture. Tune `circleMinTurn`, `circleMinSize`, `circleWindow` |
| The circle also switches screens | The camera read your hand as one finger while it moved. A new pose now only counts when the hand is held still while showing it (`poseStableRadius`, 0.04), so hold a flat open palm still for a beat, then draw the circle. After a swipe, do the same before circling, because the engine is still in one-finger mode |
| The circle fires but dictation does not start or stop | The macOS Dictation shortcut must equal `--voice-key`, and the app running AirSwipe needs Accessibility permission. Try `airswipe --focus-claude` |
| The thumbs up does not send, or a fist sends | `--debug`: `thumb=a/b` is the thumb's straightness and how far up it points. A thumbs up needs `a` ≥ 0.95, `b` ≥ 0.80 and the four fingers curled tightly (their average `str=` ≤ 0.50): squeeze the fingers. Hold it 0.7 s |

## How it works

```
CameraSource ─frames→ HandTracker ─HandSample?→ GestureEngine ─GestureEvent→ ActionMapper ─Action→ ActionSink
 (AVFoundation)        (Vision + pose + pinch)   (pure state machine)          (pure)               (CGEvent / console)
```

```
Sources/AirSwipeCore/    pure logic, no camera or AppKit, fully unit-tested
  GestureEngine          arming, modes, swipes with a return guard, fist stop, send
  PinchScroller          pinch grab / follow / release
  CircleDetector         palm circle: turn, size, roundness and closure over a sliding window
  HandPoseClassifier     poses from finger straightness; thumbs up vs fist
  ActionMapper, KeyChord events to actions; key chord parsing
Sources/airswipe/        camera, Vision, CGEvent, menu bar, accessibility
  CameraSource, HandTracker, Sinks, StatusItem, ClaudePromptFocus, main
Tests/AirSwipeCoreTests  171 tests
docs/superpowers/        design specs, plans and the key-press spike
```

```bash
swift test
```

Design and decisions: [`docs/superpowers/specs`](docs/superpowers/specs/2026-10-15-airswipe-design.md)
and the [voice design](docs/superpowers/specs/2026-10-16-voice-circle-design.md).

## Status and known limits

- Built and tuned on one person's hand, one Mac camera and one room, over several
  live sessions. Thresholds are starting values you may need to adjust.
- One hand, one camera, reasonable light. Hand pose runs continuously while the app is
  open, which costs CPU and battery.
- Your fingers and knuckles have to stay inside the picture; if the hand leaves the
  frame for about a second it stops (`disarmed (hand out of view)`).
- It sends keyboard shortcuts and scroll events, not true trackpad gestures, so a swipe
  only does something where `Ctrl+←/→` (or `Cmd+[` / `Cmd+]` with `--history`) would.
- Voice finds the Claude message box by its accessibility label ("Prompt"), so an app
  update that renames it would break the automatic focus (`--voice-target frontmost`
  is the fallback). The 🎙 mark is an assumption: AirSwipe cannot see whether
  dictation is really running.
- A command-line tool, not packaged as an `.app`, signed or notarized.
