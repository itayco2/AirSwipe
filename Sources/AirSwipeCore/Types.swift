import Foundation

/// One observation of the tracked hand, expressed from the *user's* point of view:
/// `x` grows toward the user's right, `y` grows upward, both normalized to 0...1.
public struct HandSample: Equatable {
    public var x: Double
    public var y: Double
    /// True for an open palm (fingers extended); false for a fist or curled hand.
    public var isOpen: Bool

    public init(x: Double, y: Double, isOpen: Bool = true) {
        self.x = x
        self.y = y
        self.isOpen = isOpen
    }
}

/// Direction the hand moved, from the user's point of view.
public enum SwipeDirection: Equatable {
    case left
    case right
}

/// What the engine reports back after each sample.
public enum GestureEvent: Equatable {
    case armed
    case disarmed
    case swipe(SwipeDirection)
    /// Continuous scroll. Positive means the hand is above the neutral height
    /// (scroll toward the top of the page). The value is `rate * dt`, where rate is
    /// -1...1 and 1 is full speed, so the sink multiplies by its pixels-per-second.
    case scroll(amount: Double)
}

/// Every tunable threshold in one place. Times are seconds; distances are
/// fractions of the camera frame (0...1).
public struct GestureConfig: Equatable {
    // Arming
    public var armHoldDuration: Double = 0.5
    public var armStillnessRadius: Double = 0.04

    // Disarming
    public var fistDisarmDuration: Double = 0.2
    public var handLostDisarmDuration: Double = 1.0
    public var idleDisarmDuration: Double = 6.0

    // Swipe
    public var swipeWindow: Double = 0.35
    public var swipeMinDistance: Double = 0.18
    public var swipeMaxVerticalRatio: Double = 0.6
    public var swipeCooldown: Double = 0.7

    // Scroll
    public var scrollDeadZone: Double = 0.06
    public var scrollFullSpeedOffset: Double = 0.30

    /// Gaps between samples longer than this are clamped when integrating scroll.
    public var maxSampleGap: Double = 0.1

    public init() {}
}
