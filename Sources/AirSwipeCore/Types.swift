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
    /// A fist with the thumb straight and pointing up. Held still, it sends the message.
    case thumbsUp
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
    /// How close the thumb tip is to the index tip, as a share of the width of the
    /// knuckles: about 0.1 when pinched, 1.3 or more with the hand open. Nil when the
    /// camera cannot read both fingertips. Unlike `pose` it does not depend on the shape of
    /// the other fingers, so it stays readable while the hand moves.
    public var pinch: Double?

    public init(x: Double, y: Double, pose: HandPose = .openPalm, pinch: Double? = nil) {
        self.x = x
        self.y = y
        self.pose = pose
        self.pinch = pinch
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
    /// Continuous scroll, from a pinch or from two fingers. Positive means the hand is above the neutral height
    /// (scroll toward the top of the page). The value is `rate * dt`, where rate is
    /// -1...1 and 1 is full speed, so the sink multiplies by its pixels-per-second.
    case scroll(amount: Double)
    /// An open palm drew a circle in the air: toggle voice dictation.
    case circle
    /// A thumbs up was held still: send the message.
    case send
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
    /// And, for the swipe pose only, the hand must stay within this distance while it shows
    /// it. One finger is the pose a camera misreads in a moving hand (a palm circle read as
    /// one finger for a moment), and a swipe is the action that misreading would fire. The
    /// open palm and two fingers are read reliably, so they take over without waiting for a
    /// still hand: a palm circle drawn right after a swipe must not stay in swipe mode.
    public var poseStableRadius: Double = 0.04
    /// A swipe is made with one finger, never an open palm. If a palm was read this recently
    /// the move is a circle or a wave, not a swipe, even while the mode has not caught up.
    public var swipePalmGuard: Double = 0.4
    /// The pose in which horizontal movement swipes.
    public var swipePose: HandPose = .oneFinger
    /// The pose in which hand height scrolls.
    public var scrollPose: HandPose = .twoFingers
    /// Strokes survive readings that are merely unclear (`.other`, `.fist`): with the
    /// hand low in the frame or moving fast the pose often reads that way, and one
    /// finger is still what the user is showing. Only a clear different pose, held
    /// steady, or this long without any one-finger reading ends stroke mode.
    public var strokePoseHold: Double = 1.0

    // Disarming
    /// How long a fist must be held to stop the engine.
    public var fistDisarmDuration: Double = 0.5
    /// The fist must also stay within this distance while it is held. Low in the
    /// frame a moving hand often reads as a fist for a moment; a real stop is still.
    public var fistStillnessRadius: Double = 0.06
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

    // Circle: an open palm drawing a circle starts and stops voice dictation. Off
    // unless `circleEnabled`, so nothing changes for anyone who does not ask for it.
    public var circleEnabled: Bool = false
    /// The circle must be completed within this many seconds. Real loops took 0.8 to 1.4
    /// s, so 2 s leaves room for a slower one while a slow drift still does not count.
    public var circleWindow: Double = 2.0
    /// The path must turn through at least this many radians in one direction. 5.5 is
    /// about 315 degrees; a person rarely closes the loop exactly.
    public var circleMinTurn: Double = 5.5
    /// The path must span at least this much across and down, in frame widths, so a hand
    /// at rest and small tremors never count.
    public var circleMinSize: Double = 0.10
    /// The nearest point may be no closer to the centre than this share of the farthest,
    /// so a line, a flat oval or a figure of eight does not count.
    public var circleMinRoundness: Double = 0.5
    /// After a circle, ignore further circles for this long.
    public var circleCooldown: Double = 1.0
    /// Frame height divided by frame width (480 / 640). Heights are scaled by it so a
    /// round motion is round in the maths.
    public var circleAspectRatio: Double = 0.75

    // Send: a thumbs up held still sends the message. Off unless `sendEnabled`, like the
    // circle, so nothing changes for anyone who does not ask for voice.
    public var sendEnabled: Bool = false
    /// How long the thumbs up must be held.
    public var sendHoldDuration: Double = 0.7
    /// A reading of `other` or `fist` in the middle of the hold is forgiven for this long,
    /// because the thumb is the joint set the camera reads least reliably.
    public var sendGrace: Double = 0.25
    /// The hand must stay within this distance while it holds the thumbs up.
    public var sendStillnessRadius: Double = 0.06

    // Pinch scroll: thumb and index fingertip touching is a finger on the glass. While
    // pinched the page follows the hand up and down; opening the pinch lifts the finger, so
    // the move back scrolls nothing. Measured on a real hand (2026-10-16): pinched 0.01 to
    // 0.17 through drags with the other fingers open or curled; open palm and one finger
    // 1.3 to 1.7; a relaxed fist 0.24 to 0.74; a thumbs up 0.54 to 0.74.
    public var pinchEnabled: Bool = true
    /// At or below this the fingertips count as touching.
    public var pinchEngageRatio: Double = 0.18
    /// At or above this they count as apart. Between the two, nothing changes, so a reading
    /// that wobbles does not make the scroll stutter.
    public var pinchReleaseRatio: Double = 0.35
    /// The pinch must hold this long before it grabs, so a fingertip brushing past does not.
    public var pinchEngageDuration: Double = 0.1
    /// And be apart this long before it lets go, so one bad reading does not drop the page.
    public var pinchReleaseDuration: Double = 0.15
    /// A pinch the camera cannot read is kept for this long, then dropped.
    public var pinchUnreadGrace: Double = 0.25
    /// Page scrolled per unit of hand movement while pinched, in full-speed-seconds per
    /// frame height (the same unit as `scrollFollowGain`). 3.0 means moving the hand 0.4 of
    /// the picture scrolls about a screen at 1200 px/s.
    public var pinchScrollGain: Double = 3.0

    public init() {}
}
