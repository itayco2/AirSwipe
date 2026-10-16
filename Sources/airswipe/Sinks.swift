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
    private let focusClaude: Bool
    private var burstPixels: Int32 = 0
    private var scrolledThisFrame = false
    private var lastReport = Date.distantPast

    init(style: CGEventSink.NavigationStyle, voiceKey: String, focusClaude: Bool) {
        self.style = style
        self.voiceKey = voiceKey
        self.focusClaude = focusClaude
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
            print(focusClaude
                  ? "  -> would focus the Claude message box, then press the voice key (\(voiceKey)) to start dictation"
                  : "  -> would press the voice key (\(voiceKey)) to start dictation")
        case .stopVoice:
            print("  -> would press the voice key (\(voiceKey)) to stop dictation")
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
    /// Brings the Claude app's message box into focus before dictation starts. Nil
    /// presses the key into whatever is focused.
    private let promptFocus: ClaudePromptFocus?
    /// Serial, so two quick circles can never interleave their key events.
    private let voiceQueue = DispatchQueue(label: "airswipe.voice-key")

    init(style: NavigationStyle, invertScroll: Bool, voiceChord: KeyChord?, focusClaude: Bool) {
        self.style = style
        self.invertScroll = invertScroll
        self.voiceChord = voiceChord
        self.promptFocus = focusClaude ? ClaudePromptFocus() : nil
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
                postChord(chord)
            }
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

    /// Starting dictation needs the cursor in a text field, so first bring the Claude
    /// message box into focus (when asked to), then press the key. The focus step can
    /// take a moment, so it runs on `voiceQueue`; the press is queued behind it.
    private func startVoice(_ chord: KeyChord) {
        guard let promptFocus else {
            postChord(chord)
            return
        }
        voiceQueue.async {
            let outcome = promptFocus.focus()
            if case .focused = outcome {
                Thread.sleep(forTimeInterval: 0.15)
            } else {
                fputs("airswipe: \(outcome); pressing the voice key anyway\n", stderr)
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
