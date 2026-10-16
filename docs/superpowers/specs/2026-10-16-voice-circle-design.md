# AirSwipe — Voice Circle Design Spec

**Date:** 2026-10-16 · **Status:** implemented; the key-press spike passed (`docs/superpowers/spike-voice-key.md`); the live camera test is pending

## Goal

Let a developer who works with Claude start and stop voice dictation by drawing a circle
in the air, without touching the keyboard. AirSwipe does no audio itself: it presses the
key that toggles dictation, and something else records and transcribes. Two targets use
the same code and differ only in the key and in who transcribes:

- **macOS Dictation** (tested). Works in the Claude desktop app's message box and in
  nearly any text field. Apple transcribes. This is the default.
- **Claude Code's command-line `/voice tap`** (not tested). Works in a terminal running
  Claude Code, and Claude transcribes. Select it with `--voice-key`.

## What the user does

1. Run `airswipe --live --voice`. Arm as usual with a still open palm.
2. Click into the message box. Draw a circle in the air with the **open palm**, in either
   direction.
3. AirSwipe presses the dictation key once. The menu bar shows 🎙. Dictation is now
   listening.
4. Talk. Then draw another circle. AirSwipe presses the key again, dictation stops and the
   text appears in the box.

## Decisions

1. **Something else does the recording.** The official docs describe no API, flag or hook
   to start or stop recording from outside, so the only way in is to press a key. This
   keeps AirSwipe free of audio code, microphone permission and speech models.
   The desktop app's Code tab has a microphone button but no keyboard shortcut for it,
   and a `voice:pushToTalk` binding has no effect there (anthropics/claude-code#59400),
   so for the app the key is the macOS Dictation shortcut.
2. **Toggle, not hold.** One circle starts, the next stops. macOS Dictation and Claude
   Code's tap mode both start and stop on the same single press, which a synthetic event
   can deliver. Claude Code's hold mode detects "held" by watching for rapid key-repeat
   events, which a single press does not produce, so hold-while-hand-up is left out.
3. **The circle is drawn with an open palm.** A circle contains sideways and vertical
   movement of 0.10 or more, so drawn with one finger it would also switch screens and
   scroll. In palm mode the engine already ignores movement (strokes only count in
   one-finger mode), so a palm circle collides with nothing and nothing has to be
   suppressed. Two fingers was rejected because it scrolls the page.
4. **Off by default.** `--voice` turns it on, because it presses a key into whatever
   app is focused. `--voice-key <chord>` sets the chord (default `ctrl+opt+d`) and
   implies `--voice`.
5. **The press must look like a real keystroke.** The spike showed that a bare
   key-down/key-up with flags on the key event starts dictation but does not stop it.
   Pressing Control and Option as their own key events, holding the key about 100 ms and
   then releasing everything both started and stopped it. The press therefore does that,
   on a background queue so the hold never blocks the camera thread.

## Detecting the circle

A new pure-engine event, `GestureEvent.circle`, tested with synthetic paths like every
other gesture. All numbers are starting values, to be tuned from real-camera logs.

- Only while armed and in palm mode (`openPalm`). Unclear pose readings (`other`,
  `fist`) do not end palm mode, the same rule one-finger mode already has, for up to
  `strokePoseHold`.
- Positions are kept for the last `circleWindow` (1.5 s). Heights are scaled by the
  frame's aspect ratio (`circleAspectRatio`, 0.75 for the 640×480 capture) so a round
  motion is round in the maths.
- It is a circle when, over that window: the path turns through at least
  `circleMinTurn` (5.5 radians, about 315°) in **one** direction, summing signed angle
  changes around the path's centre; its extent is at least `circleMinSize` (0.10) across
  and down; and its radius stays within a factor of two (`circleMinRoundness` 0.5), so a
  straight line or a flat oval does not count.
- A back-and-forth wave turns by about zero and a straight or zigzag path is not round,
  so neither counts. A palm held still, even with jitter, is far below the size
  threshold.
- **Known exception:** the first loop of a figure of eight is itself a round loop
  (0.12 across, a full turn), and a detector that decides as the hand moves cannot know
  a second, cancelling loop is coming, so it fires once when that loop closes. No
  threshold can reject that lobe without also rejecting real circles. (An earlier draft
  of this spec claimed a figure of eight would not count; building the detector showed
  that was wrong.)
- After a circle fires, the path is cleared and a `circleCooldown` (1 s) follows, so the
  tail of the motion cannot fire a second one.

## Plumbing

- `ActionMapper`: `.circle` becomes a new `Action.toggleVoice`.
- `KeyChord` (pure, in the core): parses `ctrl`, `opt`/`alt`/`meta`, `cmd`, `shift` plus
  one key (letter, digit, `space`, `\`, `f1`–`f20`) into a key code and modifiers.
- `CGEventSink` (live): posts the chord as a realistic press (see decision 5).
- `ConsoleSink` (dry run): prints "would press the voice key … to start or stop recording".
- `StatusItemController`: a 🎙 mark next to `ON` while recording is assumed. AirSwipe
  cannot see whether dictation is really running, so it assumes each circle flips it,
  and it resets when AirSwipe disarms.
- `main.swift`: `--voice` and `--voice-key`; `--help` and the README list them.

## User setup (once)

**Claude app and any text field (macOS Dictation):**

1. System Settings > Keyboard > Dictation: turn Dictation on.
2. Set its **Shortcut** to **Customize…** and press **Control + Option + D**.
3. Run `airswipe --live --voice` from a shell that has Accessibility permission (the
   Claude app's Terminal panel or Terminal.app; allow it under System Settings > Privacy &
   Security > Accessibility). Click into the message box before circling.

**Claude Code in a terminal (command-line tool, untested):** run `/voice tap`, bind
`voice:pushToTalk` to a chord in `~/.claude/keybindings.json` (for example
`{ "bindings": [ { "context": "Chat", "bindings": { "meta+k": "voice:pushToTalk" } } ] }`),
turn on Terminal.app's "Use Option as Meta key", and run `airswipe --live --voice-key meta+k`.
That route needs a claude.ai login and microphone permission for the terminal app, and
audio goes to Anthropic for transcription.

## Build order

1. **Spike: done.** See `docs/superpowers/spike-voice-key.md`.
2. `KeyChord`, test-first.
3. Engine: `circle` detection, test-first.
4. Engine wiring, mapper, sinks, status item, flags.
5. README, then a live test with the camera.

## Tests

- Circle: fires for a clockwise and a counter-clockwise palm circle, at several sizes
  and speeds that finish within the window; fires once, not twice, for one circle; fires
  again after the cooldown.
- Does not fire: a half circle, a straight line, a back-and-forth wave (straight and
  diagonal), a zigzag squiggle, a small wobble, a slow drift (a circle that takes longer
  than the window), a still palm with jitter, any one-finger or two-finger motion, and
  anything while not armed.
- One-finger swipes and flicks are unchanged, and a palm circle emits no swipe, flick or
  scroll.
- Mapper: `.circle` gives `[.toggleVoice]`. Chord parser: valid and invalid chords.
- The realistic key press is verified by hand (the spike method), not by unit tests.

## Known limits

- It presses a key into whatever app is focused, so the message box must be focused when
  you circle.
- The key press must come from a process with Accessibility permission. The assistant's
  own sandboxed shell has none; the Claude app's Terminal panel and Terminal.app work.
- The 🎙 mark is an assumption and can be wrong if dictation stops by itself; the next
  circle then starts a new session.
- macOS Dictation is Apple's transcription, not Claude's. The command-line route uses
  Claude's but works only in a terminal.

## Non-goals

AirSwipe doing its own recording or transcription, press-and-hold-while-the-hand-is-up,
reading the real dictation state, clicking the app's microphone button, and any platform
other than macOS.
