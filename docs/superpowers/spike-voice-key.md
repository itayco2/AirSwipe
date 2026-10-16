# Voice key spike: result

- Date: 2026-10-16
- App: the Claude desktop app (Code tab), macOS 15.5, prompt box focused
- Target: macOS Dictation, shortcut set to Control + Option + D (System Settings > Keyboard > Dictation > Shortcut > Customize…)
- Tool: a throwaway script (`spike-key.swift`, not kept) posting the chord with `CGEvent` at the HID event tap

| Press method | First press (start) | Second press (stop) | Notes |
|---|---|---|---|
| Key down and key up back to back, modifier flags set on the key event only | Dictation started | **Kept listening** | A real press of the same shortcut did stop it, so only the fake press was at fault |
| Modifier keys posted as their own `flagsChanged` events, key held 100 ms, modifiers released after | Dictation started | **Stopped, and the spoken sentence was typed into the message box** | Both presses behaved like a real keyboard |

**Decision:** the voice key is pressed the way a real keyboard presses it: Control and Option as their own key events, then the key held about 100 ms, then released, then the modifiers released. The default chord is `ctrl+opt+d`, with the user's macOS Dictation shortcut set to match. The press runs on a background queue so the 100 ms hold never blocks the camera thread.

## What we learned

1. **The target is macOS Dictation, not Claude Code's `/voice`.** The user works in the Claude desktop app. A GitHub issue (anthropics/claude-code#59400) reports that the app's Code tab has a microphone button but no keyboard shortcut, and that a `voice:pushToTalk` entry in `~/.claude/keybindings.json` has no effect there. macOS Dictation works in the app's message box, toggles on one shortcut, and needs no Claude-specific setup.
2. **A bare key-down and key-up is enough to start dictation but not to stop it.** Which of the two extra things fixed the stop (the 100 ms hold, or the separate modifier events) was not isolated; the production code does both.
3. **The assistant's own sandboxed shell cannot post key events** (Accessibility is not granted to it, and it printed a warning). The press has to come from a shell that has Accessibility permission, such as the Claude app's Terminal panel or Terminal.app.
4. **Not tested:** the Claude Code command-line route (`/voice tap` with a `voice:pushToTalk` binding in a terminal). The same `--voice-key` option can drive it, but no one has verified that route yet.

`~/.claude/keybindings.json` (with a `meta+k` binding) was created for the first spike attempt. It only affects the command-line tool and is harmless; it can be deleted.
