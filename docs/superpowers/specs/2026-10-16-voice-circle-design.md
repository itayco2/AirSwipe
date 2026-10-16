# AirSwipe — Voice Circle Design Spec

**Date:** 2026-10-16 · **Status:** design approved in chat, spec awaiting review

## Goal

Let a developer using Claude Code start and stop voice dictation by drawing a circle
in the air, without touching the keyboard. AirSwipe does no audio itself: it presses
Claude Code's own push-to-talk key, and Claude Code records, transcribes and puts the
text in the prompt box.

## What the user does

1. Run `airswipe --live --voice`. Arm as usual with a still open palm.
2. Draw a circle in the air with the **open palm**, in either direction.
3. AirSwipe presses the voice key once. The menu bar shows 🎙. Claude Code is now recording.
4. Talk. Then draw another circle. AirSwipe presses the key again, Claude Code stops
   and the transcript appears in its prompt box (Enter submits, unless `autoSubmit`).

## Decisions

1. **Claude Code does the recording.** The official docs describe `/voice` (push to
   talk with `Space`), `/voice tap` (press once to start, once to stop and send) and a
   rebindable action `voice:pushToTalk` in the `Chat` context of
   `~/.claude/keybindings.json`. There is no documented API, flag or hook to start or
   stop recording from outside, so the only way in is to press the key. This keeps
   AirSwipe free of audio code, microphone permission and speech models.
2. **Toggle, not hold.** One circle starts, the next stops. Claude Code's *tap* mode
   starts on a single key press, which a synthetic event can deliver. Its *hold* mode
   detects "held" by watching for rapid key-repeat events from the terminal, which a
   single synthetic press does not produce, so hold-while-hand-up is left out for now.
3. **The circle is drawn with an open palm.** A circle contains sideways and vertical
   movement of 0.10 or more, so drawn with one finger it would also switch screens and
   scroll. In palm mode the engine already ignores movement (strokes only count in
   one-finger mode), so a palm circle collides with nothing and nothing has to be
   suppressed. Two fingers was rejected because it scrolls the page.
4. **Off by default.** `--voice` turns it on, because it presses a key into whatever
   app is focused. `--voice-key <chord>` sets the chord, for example `meta+k`.

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
  `circleMinTurn` (about 320°) in **one** direction, summing signed angle changes
  around the path's centre; its extent is at least `circleMinSize` (0.10) across and
  down; and its radius stays within a factor of two (`circleMinRoundness` 0.5), so a
  straight line or a flat oval does not count.
- A back-and-forth wave turns by about zero, and a figure of eight turns by +360° then
  -360°, so both cancel and neither counts. A palm held still, even with jitter, is far
  below the size threshold.
- After a circle fires, the path is cleared and a `circleCooldown` (1 s) follows, so the
  tail of the motion cannot fire a second one.

## Plumbing

- `ActionMapper`: `.circle` becomes a new `Action.toggleVoice`.
- `CGEventSink` (live): posts the chord once (key down, key up) with the right modifier
  flags. A small chord parser reads `ctrl`, `opt`/`alt`/`meta`, `cmd`, `shift` plus one
  key (letter, digit, `space`, `f1`–`f20`).
- `ConsoleSink` (dry run): prints "would start/stop voice recording".
- `StatusItemController`: a 🎙 mark next to `ON` while recording is assumed. AirSwipe
  cannot see Claude Code's real state, so it assumes each circle flips it, and it resets
  when AirSwipe disarms.
- `main.swift`: `--voice` and `--voice-key`; `--help` and the README list them.

## User setup (once, in Claude Code)

`/voice tap`, and bind `voice:pushToTalk` to the same chord AirSwipe presses:

```json
{ "bindings": [ { "context": "Chat", "bindings": { "meta+k": "voice:pushToTalk" } } ] }
```

Claude Code needs a claude.ai login (voice is unavailable with API keys, Bedrock,
Vertex or Foundry), and macOS microphone permission for the terminal app. Audio goes to
Anthropic for transcription.

## Build order

1. **Spike (a nod, then throwaway code).** A small script posts a chord to a terminal
   where Claude Code is in `/voice tap` mode. Does recording start, and which chord
   reaches Claude Code reliably? Candidates: `meta+k` (the docs' example, needs "Option as
   Meta" in the terminal), `ctrl+\`, an F-key such as `f13`. If no synthetic chord
   works, stop and revisit this design before writing more.
2. Engine: `circle` detection, test-first.
3. Mapper, sinks, status item, flags.
4. README and this spec, then a live test.

## Tests

- Circle: fires for a clockwise and a counter-clockwise palm circle, at several sizes
  from 0.10 to 0.4 and speeds that finish within the window; fires once, not twice, for
  one circle; fires again after the cooldown.
- Does not fire: a half circle, a straight line, a back-and-forth wave, a figure of
  eight, a small wobble, a slow drift (a circle that takes longer than the window), a
  still palm with jitter, any one-finger or two-finger motion, and anything while not
  armed.
- One-finger swipes and flicks are unchanged, and a palm circle emits no swipe, flick or
  scroll.
- Mapper: `.circle` gives `[.toggleVoice]`. Chord parser: valid and invalid chords.

## Known limits

- It works only while a terminal running Claude Code is focused, with `/voice tap` on.
- The Claude desktop app's Code tab is not covered by the voice docs.
- The 🎙 mark can be wrong if Claude Code stops by itself (15 s of silence, or 2 minutes);
  the next circle simply starts a new recording.
- A synthetic key press may behave differently from a real one; the spike decides.

## Non-goals

AirSwipe doing its own recording or transcription, press-and-hold-while-the-hand-is-up,
reading Claude Code's recording state, and any platform other than macOS.
