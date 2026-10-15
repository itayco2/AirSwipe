import AirSwipeCore
import ApplicationServices
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
    private var burstPixels: Int32 = 0
    private var scrolledThisFrame = false
    private var lastReport = Date.distantPast

    init(style: CGEventSink.NavigationStyle) {
        self.style = style
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
        /// Move between desktops (Spaces): Ctrl+Left and Ctrl+Right.
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

    init(style: NavigationStyle, invertScroll: Bool) {
        self.style = style
        self.invertScroll = invertScroll
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

    private func postScroll(_ pixels: Int32) {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                            wheel1: pixels, wheel2: 0, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }
}
