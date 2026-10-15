import AirSwipeCore
import ApplicationServices
import CoreGraphics
import Foundation

/// Where actions go. A dry run prints them; live mode posts real events.
protocol ActionSink {
    func perform(_ action: Action)
}

/// Dry run: says what would happen and touches nothing.
final class ConsoleSink: ActionSink {
    private var pendingScroll: Int32 = 0
    private var lastScrollReport = Date.distantPast

    func perform(_ action: Action) {
        switch action {
        case .back:
            print("  -> would go BACK")
        case .forward:
            print("  -> would go FORWARD")
        case .scroll(let pixels):
            // Scroll arrives every frame; summarize a few times a second so it
            // does not drown out the swipe messages.
            pendingScroll += pixels
            let now = Date()
            guard now.timeIntervalSince(lastScrollReport) >= 0.3 else { return }
            let direction = pendingScroll >= 0 ? "UP" : "DOWN"
            print("  -> would scroll \(direction) \(abs(pendingScroll)) px")
            pendingScroll = 0
            lastScrollReport = now
        }
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
        case .back:
            switch style {
            case .browserHistory: postKey(Key.leftBracket, flags: .maskCommand)
            case .desktops: postKey(Key.leftArrow, flags: .maskControl)
            }
        case .forward:
            switch style {
            case .browserHistory: postKey(Key.rightBracket, flags: .maskCommand)
            case .desktops: postKey(Key.rightArrow, flags: .maskControl)
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
