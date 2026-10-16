# AirSwipe

Switch screens and scroll on your Mac by moving your hand in the air. It uses only
the built-in camera and Apple's Vision framework, and everything runs on-device.

**The number of fingers is the command, and one finger does most of it.**

| You show | It does |
|---|---|
| ✋ Open palm, held still ~0.5 s | **Start.** Menu-bar icon shows `ON` |
| ☝️ One finger, move **right / left** | **Switch screen**, like a 3- or 4-finger trackpad swipe between full-screen apps and desktops (`Ctrl+←/→`) |
| ☝️ One finger, flick **up / down** | **Scroll:** the page follows your hand, so the farther you flick the more it scrolls |
| ✌️ Two fingers, move your hand up / down | **Fine scroll:** the page follows your hand |
| ✊ Fist, held still ~0.5 s (or hand out of view) | **Stop** |
| ✋ Open palm, draw a **circle** (with `--voice`) | **Start / stop voice dictation** in the message box you are focused on |

Swipe **right** to go to the screen on the **left**, and swipe **left** to go to
the screen on the **right**, exactly as on the trackpad: your hand pushes the
current screen away and the next one slides in. Chrome and your other app need to
be on different screens (full-screen apps or separate desktops) for this to have
an effect. Prefer back/forward inside one app? Run with `--history`.

**Flick to scroll.** With the same one finger, a quick move up starts scrolling
toward the top of the page and a quick move down toward the bottom. The page then
follows your hand for as long as it keeps going that way, so the distance scrolled
is how far you moved: a short flick scrolls a little and a long one scrolls a lot.
Stop moving and it stops. A diagonal move is neither a swipe nor a flick. How much
page you get per hand distance is `flickScrollGain`.

**The return never counts.** After a swipe or a flick, your hand has to come back
before anything else registers, and the move back is ignored, however far it goes.
For up and down that means: flick, bring your hand back to the middle, and the next
flick works straight away, with no pause needed. (There is no "bounce" up and down:
a hand returning to the middle overshoots it by nearly as much as a deliberate
flick needs, so the way back can't be told from a new flick.) Sideways, a move that
carries on a full stroke *past* the middle still counts as a swipe the other way.
The guard also lifts if you rest anywhere for about 1.5 s, or after 3 s, so it
can't get stuck. Up and down need less distance than left and right, since a hand
held low has little room below it.

The pose decides what a movement means, so gestures can't be confused: strokes
only count in the one-finger pose and fine scrolling only in the two-finger pose.
A pose has to be steady for a moment before it counts, so a flicker between poses
can't switch modes. One-finger mode is stickier still: a reading that is merely
unclear (the camera calling it `other` or `fist` for a few frames, which happens
when your hand is low or moving fast) does not end it, and neither does a little
finger that sticks out. It ends when you show a clear different pose, or after
about a second with nothing that looks like one finger.

**Fine scroll follows your hand,** like two fingers on a trackpad: move up and the
page scrolls up, move down and it scrolls down, hold still and it stops.
(`--rate-scroll` restores the older model where hand height sets the speed.)

**Voice dictation (`--voice`).** Draw a circle in the air with your **open palm**, in
either direction, and AirSwipe presses your dictation shortcut: dictation starts.
Talk, then draw another circle: dictation stops and the text lands in the message box
you are focused on. AirSwipe records no audio itself; macOS Dictation does the
listening and Apple does the transcribing. A palm is used because a circle drawn with
one finger would also switch screens and scroll. It is off unless you pass `--voice`,
because it presses a key into whatever app is in front.

One-time setup:

1. System Settings > Keyboard > Dictation: turn Dictation on.
2. Set its **Shortcut** to **Customize…** and press **Control + Option + D**. (Any
   other chord works if you pass the same one as `--voice-key`.)
3. Run `airswipe --live --voice` from a shell that has Accessibility permission, such
   as the Claude app's Terminal panel or Terminal.app. Click into the message box
   before you circle.

The key is pressed the way a real keyboard presses it (modifier keys as their own
events, the key held about 100 ms). A bare key-down and key-up starts Dictation but
cannot stop it; see `docs/superpowers/spike-voice-key.md`.

For Claude Code's command-line tool (not tested yet), run `/voice tap`, bind
`voice:pushToTalk` to a chord in `~/.claude/keybindings.json`, turn on Terminal.app's
"Use Option as Meta key", and run `airswipe --live --voice-key meta+k`. That route
needs a claude.ai login and microphone permission for the terminal app, and the audio
goes to Anthropic.

**It works with your hand held low.** Poses come from how *straight* each finger
is, which needs only the finger's own joints. The wrist, which is out of view when
a hand rests above the keyboard, isn't used, and neither is the size or angle of
the hand.

## Status

- **Gesture logic** (`AirSwipeCore`): built test-first, 151 passing tests.
- **Camera layer** (`airswipe`): run on a real camera over several sessions, and
  the thresholds were set from those logs. Live swipes and flicks were tried and
  look good. The scroll that follows a flick, and the still-fist stop, are newer
  and tuned only from replaying recorded logs, so treat their feel (`flickScrollGain`,
  `fistStillnessRadius`) as tunable.

## Requirements

- macOS 13 or later, Apple Silicon or Intel
- Swift 5.9+ (the Xcode Command Line Tools are enough; Xcode.app is not needed)
- For switching screens: *Move left/right a space* turned on under System Settings >
  Keyboard > Keyboard Shortcuts > Mission Control (it is on by default)

## First run

```bash
swift run airswipe            # dry run: prints what it would do, posts nothing
swift run airswipe --live     # really posts screen-switch and scroll events
```

Run it from Terminal.app or iTerm. macOS will ask for **Camera** access for that
terminal app. `--live` also needs **Accessibility** access for the same app
(System Settings > Privacy & Security > Accessibility); without it macOS drops
the events silently.

Start with the dry run and watch the messages before using `--live`. Scrolling
goes to whatever is under the mouse pointer, so rest it over the page.

## Test checklist (about 3 minutes)

1. In **Terminal.app**, `cd` into this folder and run `swift run airswipe`.
2. Click **Allow** on the camera prompt.
3. Hold a flat open palm still. Expect `armed: hand gestures are on`.
4. Show **one finger** (index up, other fingers curled), pause a beat, then swipe
   to **your right**. Expect `swipe right`, then `would move to the screen on the
   LEFT`. Bring your hand back to the middle: **nothing should fire**. Then swipe
   left: `swipe left`, then `would move to the screen on the RIGHT`.
5. Still with one finger, flick your hand **up** a short way, then bring it back to
   the middle. Expect `flick up` and `would scroll UP` with a few hundred pixels,
   and nothing on the way back. Flick **up** again, farther: it scrolls more. Then
   flick **down**: `flick down`, `would scroll DOWN`.
6. Optional: show **two fingers** and move your hand up and down for fine scroll.
7. Go back to an open palm and move around. Nothing should happen.
8. Hold a fist **still** for about half a second. Expect `disarmed (fist held)`. A
   fist that is moving does not stop it.
9. If something is off, run with `--debug` and look at `mode=` and `pose=`: they
   should read `oneFinger` / `twoFingers` for the pose you are showing.

## Options

| Flag | Effect |
|---|---|
| *(none)* | Dry run |
| `--live` | Post real key and scroll events |
| `--voice` | An open-palm circle starts and stops voice dictation by pressing its shortcut (default `ctrl+opt+d`) |
| `--voice-key CHORD` | The chord to press, like `ctrl+opt+d` or `meta+k`. Implies `--voice` |
| `--history` | Swipes go back/forward inside an app (`Cmd+[` / `Cmd+]`) instead of switching screens |
| `--invert-scroll` | Flip the scroll direction (flicks and fine scroll) |
| `--rate-scroll` | Fine scroll by hand height (speed) instead of following the hand |
| `--no-mirror` | Do not mirror the camera horizontally |
| `--debug` | Print what the camera layer sees about ten times a second (engine mode and return-guard state, hand found, per-finger straightness, pose, knuckle position, armed state). When a move was big enough to be a stroke but was turned down, the line ends with `REJECTED` and the reason |

## If it feels wrong

| Symptom | Try |
|---|---|
| Swipe right moves to the wrong side | `--no-mirror` |
| Swiping does nothing to Chrome or your other app | They must be on different screens (full-screen apps or desktops). Check that *Move left/right a space* is on in Mission Control keyboard shortcuts |
| Flick up scrolls the wrong way | `--invert-scroll` |
| A flick scrolls too far or too little | `flickScrollGain` in `GestureConfig` (default 2.0: a move of 0.2 of the picture scrolls about half a screen) |
| A flick scrolls and then the page stops too soon, or keeps going on your way back | `flickFollowReversal` (default 0.015): how far the hand may slip back before the flick counts as over |
| It stops when you didn't mean to | A fist must be held still: `fistStillnessRadius` (default 0.06) and `fistDisarmDuration` (0.5 s) |
| Swipes are missed | Lower `swipeMinDistance` (default 0.12 of the frame) or raise `swipeWindow` |
| Flicks are missed, or a flick down does not register | Lower `flickMinDistance` (default 0.08 of the frame). Hold your hand a little higher in the picture so there is room to move down. After a flick, bring your hand back to the middle before the next one |
| A flick up or down is missed, or comes out the wrong way | Run with `--debug` and make the move. A `REJECTED` tail names the cause: `mode is …` (the pose was not one finger for long enough), `held by return guard` (the hand had not come back, or the carry-on was too short), `held by cooldown`, or `too far off the axis`. Also check `y=`: a hand resting near 0 has no room to move down |
| Diagonal moves fire when they shouldn't, or are ignored when they should count | `swipeMaxVerticalRatio` (how far off-axis a stroke may drift, default 0.6) |
| It never arms | Hold the palm flat and still, face the camera, add light |
| The circle does nothing | Arm first, use an **open palm**, and draw it within 1.5 s and at least 0.10 of the picture across and down. `--debug` should show `mode=openPalm` while you draw. Tune `circleMinTurn`, `circleMinSize`, `circleWindow` |
| The circle fires but dictation does not start or stop | The macOS Dictation shortcut must equal `--voice-key`. Click into the message box first. The app running AirSwipe needs Accessibility permission. A second circle within 1 s is ignored (`circleCooldown`) |
| A figure of eight fires once | Its first loop is a round loop, and a detector that decides as the hand moves cannot know a second loop follows |
| One or two fingers are not recognized | `--debug`: `str=` is each finger's straightness. Extended fingers read about 0.98 to 1.00 and curled ones 0.9 or less. Curl the other fingers tighter, or tune `extendedStraightness` / `curledStraightness` in `HandPoseClassifier` |
| It switches modes too slowly or too eagerly | `poseStableDuration` in `GestureConfig`. `strokePoseHold` (default 1 s) is how long one-finger mode survives with no one-finger reading |
| Flicks work with your hand high but not low | The camera reads a hand at the bottom edge badly (the pose turns to `other` or `fist`, the hand can drop out). Hold it so your knuckles sit about mid-picture, with room to move down |
| A stroke is ignored right after another one | The return guard is waiting for your hand to come back to where the stroke started. Return there, or rest about 1.5 s. Tune `swipeReturnGuard` and `swipeHomeRadius` |
| Fine scroll is too fast or too slow | `scrollFollowGain` (default 2.5) |
| Fine scroll jitters with your hand at rest | Raise `scrollFollowDeadband` or lower `scrollSmoothing` |

Every threshold is a field of `GestureConfig` in
`Sources/AirSwipeCore/Types.swift`, with times in seconds and distances as a
fraction of the camera frame.

## How it works

```
CameraSource ─frames→ HandTracker ─HandSample?→ GestureEngine ─GestureEvent→ ActionMapper ─Action→ ActionSink
 (AVFoundation)        (Vision + pose)          (pure state machine)          (pure)               (CGEvent / console)
```

`HandTracker` turns the Vision joints into a knuckle position and a `HandPose`.
The engine takes timestamped samples and returns events (`swipe`, `flick`,
`scroll`). It has no camera or clock, so false positives can be tested with
synthetic hand paths:

```bash
swift test
```

Design and plan: [`docs/superpowers/specs`](docs/superpowers/specs/2026-10-15-airswipe-design.md),
[`docs/superpowers/plans`](docs/superpowers/plans/2026-10-15-airswipe.md).

## Known limits

- One hand, one camera, and it needs reasonable light.
- Hand pose runs continuously while the app is open, which costs CPU and battery.
- Poses come from finger straightness, a geometric measure that may need tuning
  for your hands and lighting. The thumb is ignored, and so is the little finger
  when telling one finger from two (it is short and often left sticking out).
- Your fingers and knuckles have to stay inside the picture. If the hand leaves
  the frame for about a second it stops (`disarmed (hand out of view)`).
- It sends keyboard shortcuts and scroll events, not true trackpad gestures, so a
  swipe only does something where `Ctrl+←/→` (or `Cmd+[` / `Cmd+]` with
  `--history`) would.
- Voice dictation presses a key into whatever app is in front, so the message box has
  to be focused when you circle. The press must come from a process with Accessibility
  permission (an assistant's own sandboxed shell has none). The 🎙 mark is an
  assumption and can be wrong if dictation stops by itself; the next circle then
  starts a new session.
- Not packaged as an `.app`, not signed or notarized.
