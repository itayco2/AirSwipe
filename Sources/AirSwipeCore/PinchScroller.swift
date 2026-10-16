import Foundation

/// Turns the thumb-to-index distance and the hand's height into a phone-style scroll:
/// while the fingertips touch, the page follows the hand up and down; opening them lifts
/// the finger, so the move back scrolls nothing and pinching again grabs it anew.
///
/// The pinch reading (`HandSample.pinch`) is a distance between two fingertips, so it
/// keeps its value while the hand moves and whatever the other fingers look like. The
/// finger-shape poses do not: one finger was read as one finger in only 52 to 66% of
/// frames while the hand moved. That is why the grab is the pinch and not a pose.
///
/// Internal to the engine, like `CircleDetector`: the engine feeds it every armed frame.
struct PinchScroller {
    /// What one frame produced.
    struct Result {
        /// The fingertips are touching, or have just started to: the engine should leave the
        /// frame alone, so a pinch is never mistaken for a fist, a thumbs up or a swipe.
        var isActive = false
        /// The page is held, so the hand is being followed.
        var isEngaged = false
        /// Scroll for this frame, positive when the hand moved up.
        var scroll = 0.0
        /// The page was let go on this frame.
        var released = false
    }

    private let config: GestureConfig

    private(set) var isEngaged = false
    private var closeSince: TimeInterval?
    private var apartSince: TimeInterval?
    private var unreadSince: TimeInterval?
    /// Smoothed hand height while the page is held.
    private var heldY: Double?

    init(config: GestureConfig) {
        self.config = config
    }

    mutating func update(pinch: Double?, y: Double, at time: TimeInterval) -> Result {
        guard config.pinchEnabled else { return Result() }

        guard let ratio = pinch else {
            // Cannot read the fingertips. A grip is kept for a moment, never started.
            closeSince = nil
            guard isEngaged else { return Result() }
            let since = unreadSince ?? time
            unreadSince = since
            if time - since >= config.pinchUnreadGrace {
                return letGo()
            }
            return Result(isActive: true, isEngaged: true)
        }
        unreadSince = nil

        if ratio <= config.pinchEngageRatio {
            apartSince = nil
            if isEngaged {
                return follow(y: y)
            }
            let since = closeSince ?? time
            closeSince = since
            if time - since >= config.pinchEngageDuration {
                isEngaged = true
                heldY = y
                return Result(isActive: true, isEngaged: true)
            }
            return Result(isActive: true)
        }

        if ratio >= config.pinchReleaseRatio {
            closeSince = nil
            guard isEngaged else { return Result() }
            let since = apartSince ?? time
            apartSince = since
            if time - since >= config.pinchReleaseDuration {
                return letGo()
            }
            // Apart, but not for long enough to be sure: hold the page, do not move it.
            return Result(isActive: true, isEngaged: true)
        }

        // Between touching and apart: nothing changes.
        apartSince = nil
        if isEngaged {
            return follow(y: y)
        }
        closeSince = nil
        return Result()
    }

    /// Forget everything, for when the hand is lost or the engine stops.
    mutating func reset() {
        isEngaged = false
        closeSince = nil
        apartSince = nil
        unreadSince = nil
        heldY = nil
    }

    /// The page follows the hand, like a finger on a trackpad: the scroll for each frame is
    /// the hand's vertical movement since the last one. The height is smoothed and tiny
    /// movements are ignored, so tremor does not scroll the page.
    private mutating func follow(y: Double) -> Result {
        let previous = heldY ?? y
        let smoothed = previous + config.scrollSmoothing * (y - previous)
        heldY = smoothed
        let delta = smoothed - previous
        var result = Result(isActive: true, isEngaged: true)
        if abs(delta) >= config.scrollFollowDeadband {
            result.scroll = delta * config.pinchScrollGain
        }
        return result
    }

    private mutating func letGo() -> Result {
        reset()
        return Result(released: true)
    }
}
