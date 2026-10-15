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

/// Why the engine stopped listening. Lets the app say what happened instead of
/// just "disarmed".
public enum DisarmReason: Equatable {
    /// A fist was held (the deliberate stop signal).
    case fist
    /// The hand was out of view for too long.
    case handLost
    /// Nothing happened for too long.
    case idle
}

/// How hand movement becomes scrolling.
public enum ScrollMode: Equatable {
    /// The page follows the hand: moving it up scrolls up, moving it down scrolls
    /// down, and holding it still stops. Like two fingers on a trackpad.
    case followHand
    /// Hand height sets speed: the farther the hand is above or below where the
    /// two-finger pose appeared, the faster the page scrolls, for as long as it
    /// stays there.
    case rate
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
    /// How far back, in seconds, a swipe's travel is measured.
    public var swipeWindow: Double = 0.40
    /// How far the hand must travel, as a fraction of the frame, to count as a swipe.
    /// Natural swipes measured about 0.14 to 0.16 wide, so this sits below that.
    public var swipeMinDistance: Double = 0.12
    public var swipeMaxVerticalRatio: Double = 0.6
    public var swipeCooldown: Double = 0.7

    /// A swipe starts from a hand that has slowed or stopped at the middle, while a
    /// return that overshoots is still moving. The hand counts as slow when it has
    /// moved at most `swipeSlowSpeed` (frame widths per second) over the last
    /// `swipeSlowWindow` seconds. Lifting the return guard also keeps only that last
    /// stretch of motion, so the turnaround point is not lost.
    public var swipeSlowWindow: Double = 0.10
    public var swipeSlowSpeed: Double = 0.30

    // Return guard: after a swipe the hand comes back toward where it started, and
    // that return must not swipe the other way. Swipes are held off until the hand
    // settles near the swipe's origin, rests elsewhere, or the guard expires.
    /// Arriving this close to the swipe's origin lifts the guard at once, so a swipe
    /// that follows the return straight away is tracked. Must stay below
    /// `swipeMinDistance`, or the end of a swipe would already count as "home".
    public var swipeHomeRadius: Double = 0.08
    /// Settling this close to the origin (still for `swipeSettleDwell`) lifts the
    /// guard too, for returns that stop a little short of the exact middle. Like
    /// `swipeHomeRadius`, it must stay below `swipeMinDistance`.
    public var swipeSettleRadius: Double = 0.10
    /// How long the hand must stay still within `swipeSettleRadius`.
    public var swipeSettleDwell: Double = 0.10
    /// How long the hand must stay still anywhere else to lift the guard.
    public var swipeRestDuration: Double = 1.5
    /// The guard lifts by itself this long after the swipe.
    public var swipeReturnGuard: Double = 3.0
    /// How far the hand may drift and still count as "still".
    public var swipeDwellRadius: Double = 0.04

    // Scroll
    public var scrollMode: ScrollMode = .followHand

    /// `.followHand`: how much to scroll per unit of vertical hand movement, in
    /// full-speed-seconds per frame height. 2.5 means moving the hand a tenth of
    /// the frame scrolls a quarter of a second at full speed.
    public var scrollFollowGain: Double = 2.5
    /// `.followHand`: how much of each new height reading is taken (0...1). Lower
    /// is steadier but lags more; it keeps hand tremor from scrolling the page.
    public var scrollSmoothing: Double = 0.4
    /// `.followHand`: smoothed movement per frame below this is ignored.
    public var scrollFollowDeadband: Double = 0.003

    /// `.rate`: no scrolling within this distance of the neutral height.
    public var scrollDeadZone: Double = 0.06
    /// `.rate`: the distance from neutral at which scrolling reaches full speed.
    public var scrollFullSpeedOffset: Double = 0.30

    /// Gaps between samples longer than this are clamped when integrating scroll.
    public var maxSampleGap: Double = 0.1

    public init() {}
}
