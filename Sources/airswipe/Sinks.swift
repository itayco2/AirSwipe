import AirSwipeCore
import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

/// Where actions go. A dry run prints them; live mode posts real events.
protocol ActionSink {
    func perform(_ action: Action)
    /// Called once after every camera frame, so a sink can flush anything it batched.
    func endFrame()
}

extension ActionSink {
    func endFrame() {}
}

/// Dry run: says what would happen and touches nothing.
final class ConsoleSink: ActionSink {
    private let style: CGEventSink.NavigationStyle
    private let voiceKey: String
    private let voiceTarget: VoiceTarget
    private var burstPixels: Int32 = 0
    private var scrolledThisFrame = false
    private var lastReport = Date.distantPast

    init(style: CGEventSink.NavigationStyle, voiceKey: String, voiceTarget: VoiceTarget) {
        self.style = style
        self.voiceKey = voiceKey
        self.voiceTarget = voiceTarget
    }

    /// What a dry run says about where the keys would go.
    private var whereKeysGo: String {
        switch voiceTarget {
        case .auto:
            return "in the app in front (focusing the Claude message box first only if that app is Claude)"
        case .claude:
            return "after bringing the Claude app forward and focusing its message box"
        case .frontmost:
            return "in whatever is focused"
        }
    }

    func perform(_ action: Action) {
        switch action {
        case .back:
            print(style == .desktops ? "  -> would move to the screen on the LEFT"
                                     : "  -> would go BACK")
        case .forward:
            print(style == .desktops ? "  -> would move to the screen on the RIGHT"
                                     : "  -> would go FORWARD")
        case .scroll(let pixels):
            burstPixels += pixels
            scrolledThisFrame = true
        case .startVoice:
            print("  -> would press the voice key (\(voiceKey)) to start dictation, \(whereKeysGo)")
        case .stopVoice:
            print("  -> would press the voice key (\(voiceKey)) to stop dictation")
        case .sendMessage:
            print("  -> would press Return to send, \(whereKeysGo)")
        }
    }

    /// Scroll arrives every frame. Report a burst once it ends (the first frame
    /// without scrolling), or every half second while it continues, so short
    /// scrolls are shown in full and long ones do not flood the terminal.
    func endFrame() {
        defer { scrolledThisFrame = false }
        guard burstPixels != 0 else { return }

        let now = Date()
        let burstEnded = !scrolledThisFrame
        guard burstEnded || now.timeIntervalSince(lastReport) >= 0.5 else { return }

        let direction = burstPixels >= 0 ? "UP" : "DOWN"
        print("  -> would scroll \(direction) \(abs(burstPixels)) px")
        burstPixels = 0
        lastReport = now
    }
}

/// Live mode: posts real keyboard and scroll-wheel events system-wide.
/// Needs Accessibility permission, or macOS drops the events silently.
final class CGEventSink: ActionSink {
    enum NavigationStyle {
        /// Back and forward in browsers and many document apps: Cmd+[ and Cmd+].
        case browserHistory
        /// Move between screens (full-screen apps and desktops): Ctrl+Left and
        /// Ctrl+Right, the same thing the trackpad's 3- or 4-finger swipe does.
        case desktops
    }

    // Virtual key codes (kVK_ANSI_LeftBracket and friends), spelled out so this
    // file needs no Carbon import.
    private enum Key {
        static let leftBracket: CGKeyCode = 0x21
        static let rightBracket: CGKeyCode = 0x1E
        static let leftArrow: CGKeyCode = 0x7B
        static let rightArrow: CGKeyCode = 0x7C
    }

    private let style: NavigationStyle
    private let invertScroll: Bool
    private let voiceChord: KeyChord?
    /// Where the keys go: see `VoiceTarget`. Whether the Claude message box is focused first
    /// is decided each time, from the app in front.
    private let voiceTarget: VoiceTarget
    private let promptFocus = ClaudePromptFocus()
    /// Serial, so two quick circles can never interleave their key events.
    private let voiceQueue = DispatchQueue(label: "airswipe.voice-key")
    /// When dictation was last told to stop. Only touched on `voiceQueue`.
    private var lastVoiceStop = Date.distantPast

    init(style: NavigationStyle, invertScroll: Bool, voiceChord: KeyChord?, voiceTarget: VoiceTarget) {
        self.style = style
        self.invertScroll = invertScroll
        self.voiceChord = voiceChord
        self.voiceTarget = voiceTarget
    }

    /// Whether the Claude message box should be focused before a key is pressed. Always for
    /// `claude`; for `auto` only when the app in front already is Claude, so a circle drawn on
    /// a YouTube page dictates into that page instead of switching the screen to Claude.
    private func shouldFocusClaude() -> Bool {
        voiceTarget.focusesClaude(
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            claudeBundleID: ClaudePromptFocus.bundleIdentifier)
    }

    /// Returns whether this process may post events, and asks macOS to show the
    /// permission prompt if it may not.
    static func requestAccessibility() -> Bool {
        // The literal is the documented value of kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func perform(_ action: Action) {
        switch action {
        // A real arrow key press also carries the function and numeric-pad flags,
        // and the system "move a space" shortcuts expect them, so match hardware.
        case .back:
            switch style {
            case .browserHistory:
                postKey(Key.leftBracket, flags: .maskCommand)
            case .desktops:
                postKey(Key.leftArrow, flags: [.maskControl, .maskSecondaryFn, .maskNumericPad])
            }
        case .forward:
            switch style {
            case .browserHistory:
                postKey(Key.rightBracket, flags: .maskCommand)
            case .desktops:
                postKey(Key.rightArrow, flags: [.maskControl, .maskSecondaryFn, .maskNumericPad])
            }
        case .scroll(let pixels):
            postScroll(invertScroll ? -pixels : pixels)
        case .startVoice:
            if let chord = voiceChord {
                startVoice(chord)
            }
        case .stopVoice:
            if let chord = voiceChord {
                // Remember when, so a send that follows can wait for the text to land.
                voiceQueue.async { self.lastVoiceStop = Date() }
                postChord(chord)
            }
        case .sendMessage:
            sendMessage()
        }
    }

    private func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Sends the message. Dictation that was only just stopped needs a moment to finish
    /// typing, so wait until `dictationSettle` has passed since the stop; then bring the
    /// Claude message box into focus (when asked to) and press Return.
    private func sendMessage() {
        let dictationSettle = 0.8
        voiceQueue.async {
            let sinceStop = Date().timeIntervalSince(self.lastVoiceStop)
            if sinceStop < dictationSettle {
                Thread.sleep(forTimeInterval: dictationSettle - sinceStop)
            }
            if self.shouldFocusClaude() {
                let outcome = self.promptFocus.focus()
                if outcome.isFocused {
                    Thread.sleep(forTimeInterval: 0.06)
                } else {
                    fputs("airswipe: \(outcome); pressing Return anyway\n", stderr)
                }
            }
            self.postChord(KeyChord(keyCode: 0x24)) // Return
        }
    }

    /// Starting dictation needs the cursor in a text field. In the Claude app that is the
    /// message box, which is focused first when `VoiceTarget` says so; anywhere else the
    /// cursor is wherever the user put it. The focus step can take a moment, so it runs on
    /// `voiceQueue`; the press is queued behind it.
    private func startVoice(_ chord: KeyChord) {
        voiceQueue.async {
            if self.shouldFocusClaude() {
                let outcome = self.promptFocus.focus()
                if case .focused = outcome {
                    Thread.sleep(forTimeInterval: 0.06)
                } else {
                    fputs("airswipe: \(outcome); pressing the voice key anyway\n", stderr)
                }
            }
            self.postChord(chord)
        }
    }

    /// Presses a chord the way a real keyboard does: each modifier as its own
    /// flagsChanged event, the key held about 100 ms, then everything released. The
    /// spike showed that a bare key-down and key-up starts macOS Dictation but cannot
    /// stop it (docs/superpowers/spike-voice-key.md). The sleeps run on `voiceQueue`,
    /// never on the camera thread.
    private func postChord(_ chord: KeyChord) {
        voiceQueue.async {
            let source = CGEventSource(stateID: .hidSystemState)
            let modifiers: [(isOn: Bool, flag: CGEventFlags, key: CGKeyCode)] = [
                (chord.control, .maskControl, 0x3B),
                (chord.option, .maskAlternate, 0x3A),
                (chord.shift, .maskShift, 0x38),
                (chord.command, .maskCommand, 0x37),
            ]
            var held: CGEventFlags = []

            func postModifier(_ key: CGKeyCode) {
                let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
                event?.type = .flagsChanged
                event?.flags = held
                event?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.02)
            }

            for modifier in modifiers where modifier.isOn {
                held.insert(modifier.flag)
                postModifier(modifier.key)
            }
            let keyCode = CGKeyCode(chord.keyCode)
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            down?.flags = chord.flags
            down?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.1)
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            up?.flags = chord.flags
            up?.post(tap: .cghidEventTap)
            for modifier in modifiers.reversed() where modifier.isOn {
                held.remove(modifier.flag)
                postModifier(modifier.key)
            }
        }
    }

    private func postScroll(_ pixels: Int32) {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                            wheel1: pixels, wheel2: 0, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }
}

private extension KeyChord {
    var flags: CGEventFlags {
        var flags: CGEventFlags = []
        if control { flags.insert(.maskControl) }
        if option { flags.insert(.maskAlternate) }
        if command { flags.insert(.maskCommand) }
        if shift { flags.insert(.maskShift) }
        return flags
    }
}
