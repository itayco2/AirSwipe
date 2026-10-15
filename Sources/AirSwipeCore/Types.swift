import Foundation

/// What the hand is showing, read from which fingers are extended.
///
/// The pose is the *mode*: it decides what a movement means. Swipes only count in
/// one pose and scrolling only in another, so the gestures cannot be confused.
public enum HandPose: Equatable {
    /// All four fingers extended. Held still, it starts (arms) the engine.
    case openPalm
    /// All four fingers curled. Held, it stops (disarms) the engine.
    case fist
    /// Only the index finger extended. Swipe mode.
    case oneFinger
    /// Index and middle fingers extended. Scroll mode.
    case twoFingers
    /// Anything else, including a hand caught between poses. Does nothing.
    case other
}

/// One observation of the tracked hand, expressed from the *user's* point of view:
/// `x` grows toward the user's right, `y` grows upward, both normalized to 0...1.
public struct HandSample: Equatable {
    public var x: Double
    public var y: Double
    public var pose: HandPose

    public init(x: Double, y: Double, pose: HandPose = .openPalm) {
        self.x = x
        self.y = y
        self.pose = pose
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

    // Modes
    /// A pose must be seen continuously this long before it changes the mode, so
    /// a flicker between poses cannot switch what a movement means.
    public var poseStableDuration: Double = 0.15
    /// The pose in which horizontal movement swipes.
    public var swipePose: HandPose = .oneFinger
    /// The pose in which hand height scrolls.
    public var scrollPose: HandPose = .twoFingers

    // Disarming
    /// How long a fist must be held to stop the engine.
    public var fistDisarmDuration: Double = 0.5
    public var handLostDisarmDuration: Double = 1.0
    public var idleDisarmDuration: Double = 15.0

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
