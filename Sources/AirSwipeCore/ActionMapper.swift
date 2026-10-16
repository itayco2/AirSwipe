import Foundation

/// What the outside world should do in response to a gesture.
public enum Action: Equatable {
    /// Previous page (browser back, or the desktop to the left).
    case back
    /// Next page (browser forward, or the desktop to the right).
    case forward
    /// Scroll by whole pixels. Positive scrolls toward the top of the page.
    case scroll(pixels: Int32)
    /// Start dictation: focus the message box if needed, then press the voice key.
    case startVoice
    /// Stop dictation: press the voice key again.
    case stopVoice
}

/// Translates gesture events into actions.
///
/// Stateful only for scrolling: the engine emits many tiny per-frame amounts, so
/// the fractional pixels left over after rounding are carried to the next call.
/// Dropping them would make slow scrolling stall.
public final class ActionMapper {
    private let maxScrollPixelsPerSecond: Double
    private var pendingPixels = 0.0

    /// Whether dictation is assumed to be running. Each circle flips it, and arming or
    /// disarming resets it: nothing can see the real state, so this is a best guess.
    public private(set) var voiceActive = false

    public init(maxScrollPixelsPerSecond: Double = 1200) {
        self.maxScrollPixelsPerSecond = maxScrollPixelsPerSecond
    }

    public func actions(for event: GestureEvent) -> [Action] {
        switch event {
        case .armed, .disarmed:
            pendingPixels = 0
            voiceActive = false
            return []

        case .swipe(.right):
            return [.back]

        case .swipe(.left):
            return [.forward]

        case .flick:
            // Only says a flick began. The page is moved by the `.scroll` events that
            // follow the hand, so this must not scroll a second time.
            return []

        case .circle:
            voiceActive.toggle()
            return [voiceActive ? .startVoice : .stopVoice]

        case .scroll(let amount):
            pendingPixels += amount * maxScrollPixelsPerSecond
            let whole = pendingPixels.rounded(.towardZero)
            guard whole != 0 else { return [] }
            pendingPixels -= whole
            return [.scroll(pixels: Int32(whole))]
        }
    }
}
