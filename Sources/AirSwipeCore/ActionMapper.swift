import Foundation

/// What the outside world should do in response to a gesture.
public enum Action: Equatable {
    /// Previous page (browser back, or the desktop to the left).
    case back
    /// Next page (browser forward, or the desktop to the right).
    case forward
    /// Scroll by whole pixels. Positive scrolls toward the top of the page.
    case scroll(pixels: Int32)
}

/// Translates gesture events into actions.
///
/// Stateful only for scrolling: the engine emits many tiny per-frame amounts, so
/// the fractional pixels left over after rounding are carried to the next call.
/// Dropping them would make slow scrolling stall.
public final class ActionMapper {
    private let maxScrollPixelsPerSecond: Double
    private var pendingPixels = 0.0

    public init(maxScrollPixelsPerSecond: Double = 1200) {
        self.maxScrollPixelsPerSecond = maxScrollPixelsPerSecond
    }

    public func actions(for event: GestureEvent) -> [Action] {
        switch event {
        case .armed, .disarmed:
            pendingPixels = 0
            return []

        case .swipe(.right):
            return [.back]

        case .swipe(.left):
            return [.forward]

        case .scroll(let amount):
            pendingPixels += amount * maxScrollPixelsPerSecond
            let whole = pendingPixels.rounded(.towardZero)
            guard whole != 0 else { return [] }
            pendingPixels -= whole
            return [.scroll(pixels: Int32(whole))]
        }
    }
}
