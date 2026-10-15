import Foundation

/// Turns a stream of timestamped hand samples into gesture events.
///
/// The engine is a pure state machine: it never reads a clock or touches the
/// camera. Time comes only from the `time` argument, which is what makes the
/// hard part of this project (false positives) testable with synthetic input.
///
/// The hand's *pose* decides what a movement means, so gestures cannot be
/// confused with each other:
///
///     open palm, held still        starts it (arms)
///     one finger                   swipe mode: left/right motion swipes
///     two fingers                  scroll mode: the page follows the hand
///     fist, held                   stops it (disarms)
///
/// A pose only becomes the mode once it has been steady for `poseStableDuration`,
/// so a flicker between poses cannot switch modes.
public final class GestureEngine {
    private enum State {
        case idle
        case armed
    }

    private let config: GestureConfig
    private var state: State = .idle

    // Idle: the arming candidate, i.e. where an open palm first settled, and when.
    private var holdAnchor: (x: Double, y: Double)?
    private var holdStart: TimeInterval = 0
    /// Set after an idle timeout. The hand must leave or change pose before it can
    /// arm again; otherwise a palm still raised would re-arm at once and flap.
    private var needsRelease = false

    // Armed: the pose that currently decides what movement means (`mode`), the
    // pose being considered for it, and the height `.rate` scrolling is measured from.
    private var mode: HandPose = .other
    private var candidatePose: HandPose = .other
    private var candidateSince: TimeInterval = 0
    private var candidateY = 0.5
    private var scrollNeutralY = 0.5
    /// Smoothed hand height while the page is following the hand.
    private var followY: Double?

    // Armed: tracking. Position is followed in every pose so that a swipe
    // survives a flicker; the mode only decides whether it counts.
    private var previousTime: TimeInterval?
    private var window: [(time: TimeInterval, x: Double, y: Double)] = []
    private var lastSwipeTime: TimeInterval = -.infinity

    // Armed: the return guard. After a swipe the hand comes back toward where it
    // started, and that return must not swipe the other way.
    private var awaitingReturn = false
    private var returnHomeX = 0.5
    private var guardSince: TimeInterval = 0
    private var dwellX = 0.5
    private var dwellSince: TimeInterval = 0

    // Armed: signals that lead to disarming.
    private var lastActivity: TimeInterval = 0
    private var fistSince: TimeInterval?
    private var lostSince: TimeInterval?

    /// Why the engine most recently disarmed, so the app can explain it.
    public private(set) var lastDisarmReason: DisarmReason?

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
    }

    /// One line describing the engine's internal state, for debugging.
    public var diagnostics: String {
        let guardText = awaitingReturn ? String(format: "ON(home=%.2f)", returnHomeX) : "off"
        return "mode=\(mode) guard=\(guardText)"
    }

    /// Feed one frame. `sample` is nil when no hand is visible.
    public func process(_ sample: HandSample?, at time: TimeInterval) -> [GestureEvent] {
        switch state {
        case .idle:
            return processIdle(sample, at: time)
        case .armed:
            return processArmed(sample, at: time)
        }
    }

    // MARK: - Idle

    /// Arm once an open palm has stayed within `armStillnessRadius` of where it
    /// settled for `armHoldDuration`. Any movement past the radius, or any other
    /// pose or no hand, restarts the hold.
    private func processIdle(_ sample: HandSample?, at time: TimeInterval) -> [GestureEvent] {
        guard let sample, sample.pose == .openPalm else {
            holdAnchor = nil
            needsRelease = false
            return []
        }
        if needsRelease { return [] }

        if let anchor = holdAnchor,
           hypot(sample.x - anchor.x, sample.y - anchor.y) <= config.armStillnessRadius {
            if time - holdStart >= config.armHoldDuration {
                state = .armed
                holdAnchor = nil
                lastActivity = time
                lastSwipeTime = -.infinity
                awaitingReturn = false
                mode = .openPalm
                candidatePose = .openPalm
                candidateSince = time
                candidateY = sample.y
                resetTracking()
                return [.armed]
            }
        } else {
            holdAnchor = (sample.x, sample.y)
            holdStart = time
        }
        return []
    }

    // MARK: - Armed

    private func processArmed(_ sample: HandSample?, at time: TimeInterval) -> [GestureEvent] {
        // No hand: ride out short dropouts, disarm after a sustained loss. A hand
        // that comes back has to show its pose afresh.
        guard let sample else {
            resetTracking()
            fistSince = nil
            candidatePose = .other
            candidateSince = time
            let since = lostSince ?? time
            lostSince = since
            return time - since >= config.handLostDisarmDuration ? disarm(.handLost) : []
        }
        lostSince = nil

        // A fist is the stop signal, and only a fist: a pose that is merely
        // in-between never disarms. It must persist, because fingers curl for a
        // moment during fast movement.
        if sample.pose == .fist {
            fistSince = fistSince ?? time
        } else {
            fistSince = nil
        }
        if let fistSince, time - fistSince >= config.fistDisarmDuration {
            return disarm(.fist)
        }

        updateMode(for: sample, at: time)
        updateReturnGuard(for: sample, at: time)

        // Clamp so a long gap (dropped frames) cannot produce a huge scroll jump.
        let dt = min(max(time - (previousTime ?? time), 0), config.maxSampleGap)
        previousTime = time

        let events = gestureEvents(for: sample, at: time, dt: dt)
        if !events.isEmpty {
            lastActivity = time
            return events
        }

        if time - lastActivity >= config.idleDisarmDuration {
            needsRelease = true
            return disarm(.idle)
        }
        return []
    }

    /// A pose becomes the mode only after it has been steady for
    /// `poseStableDuration`. Entering scroll mode records the height it started
    /// at, which `.rate` scrolling is measured from.
    private func updateMode(for sample: HandSample, at time: TimeInterval) {
        if sample.pose != candidatePose {
            candidatePose = sample.pose
            candidateSince = time
            candidateY = sample.y
        }
        if mode != candidatePose, time - candidateSince >= config.poseStableDuration {
            mode = candidatePose
            followY = nil
            if mode == config.scrollPose {
                scrollNeutralY = candidateY
            }
        }
    }

    /// While a swipe's return is pending, watch for the hand to come back. The
    /// guard lifts when the hand has arrived back at the swipe's origin (the
    /// middle) and slowed down, so a swipe that follows without a pause is tracked
    /// while a return that overshoots is not. It also lifts when the hand settles a
    /// little short of the middle, when it has rested anywhere for a while, or on
    /// its own after `swipeReturnGuard`, so it can never leave swiping stuck off.
    private func updateReturnGuard(for sample: HandSample, at time: TimeInterval) {
        guard awaitingReturn else { return }

        if abs(sample.x - dwellX) > config.swipeDwellRadius {
            dwellX = sample.x
            dwellSince = time
        }
        let dwell = time - dwellSince

        // Back at the middle, and either turning around or slowing down. A return
        // that overshoots does neither until it is well past the middle.
        let atHome = abs(sample.x - returnHomeX) <= config.swipeHomeRadius
        var turnedAround = false
        if window.count >= 2 {
            let last = window[window.count - 1].x
            let before = window[window.count - 2].x
            turnedAround = (last - before) * (sample.x - last) < 0
        }
        let arrivedHome = atHome && (turnedAround || isSlow(at: time, x: sample.x))
        let settledNearHome = abs(dwellX - returnHomeX) <= config.swipeSettleRadius
            && dwell >= config.swipeSettleDwell
        let restedAway = dwell >= config.swipeRestDuration
        let expired = time - guardSince >= config.swipeReturnGuard

        if arrivedHome || settledNearHome || restedAway || expired {
            awaitingReturn = false
            // The window still holds the return stroke. Left in place it would
            // fire as a swipe the instant the guard lifts. Keep only the last
            // stretch, which is the slow turnaround a new swipe starts from.
            window.removeAll { time - $0.time > config.swipeSlowWindow }
        }
    }

    /// True once the hand has (nearly) stopped: it moved little over the last
    /// `swipeSlowWindow` seconds. Needs that much history, and is false without it.
    private func isSlow(at time: TimeInterval, x: Double) -> Bool {
        guard let reference = window.last(where: { time - $0.time >= config.swipeSlowWindow }) else {
            return false
        }
        let elapsed = time - reference.time
        return abs(x - reference.x) / elapsed <= config.swipeSlowSpeed
    }

    private func gestureEvents(for sample: HandSample, at time: TimeInterval,
                               dt: Double) -> [GestureEvent] {
        if let direction = detectSwipe(sample, at: time) {
            return [.swipe(direction)]
        }
        guard mode == config.scrollPose else { return [] }
        return scroll(for: sample, dt: dt)
    }

    /// A swipe is a fast, mostly horizontal move made in swipe mode. Its travel is
    /// measured from the turnaround point in the recent window, not from the
    /// oldest sample, so a swipe straight after a return keeps the distance the
    /// hand covered on its way back to the middle. After one fires, further swipes
    /// are suppressed for `swipeCooldown`, and then until the hand has returned
    /// (see `updateReturnGuard`), which keeps the return stroke from swiping the
    /// other way.
    private func detectSwipe(_ sample: HandSample, at time: TimeInterval) -> SwipeDirection? {
        window.append((time, sample.x, sample.y))
        window.removeAll { time - $0.time > config.swipeWindow }

        guard mode == config.swipePose,
              !awaitingReturn,
              time - lastSwipeTime >= config.swipeCooldown,
              let low = window.min(by: { $0.x < $1.x }),
              let high = window.max(by: { $0.x < $1.x }) else {
            return nil
        }

        let rightward = sample.x - low.x
        let leftward = high.x - sample.x
        let isRight = rightward >= leftward
        let travel = isRight ? rightward : leftward
        let origin = isRight ? low : high

        guard travel >= config.swipeMinDistance,
              abs(sample.y - origin.y) <= config.swipeMaxVerticalRatio * travel else {
            return nil
        }

        lastSwipeTime = time
        awaitingReturn = true
        returnHomeX = origin.x
        guardSince = time
        dwellX = sample.x
        dwellSince = time
        window.removeAll()
        return isRight ? .right : .left
    }

    private func scroll(for sample: HandSample, dt: Double) -> [GestureEvent] {
        switch config.scrollMode {
        case .followHand:
            return followScroll(for: sample)
        case .rate:
            return rateScroll(for: sample, dt: dt)
        }
    }

    /// The page follows the hand, like two fingers on a trackpad: the scroll for
    /// each frame is the hand's vertical movement since the last one. Holding the
    /// hand still stops it. The height is smoothed and tiny movements are ignored,
    /// so hand tremor does not scroll the page.
    private func followScroll(for sample: HandSample) -> [GestureEvent] {
        let previous = followY ?? sample.y
        let smoothed = previous + config.scrollSmoothing * (sample.y - previous)
        followY = smoothed

        let delta = smoothed - previous
        guard abs(delta) >= config.scrollFollowDeadband else { return [] }
        return [.scroll(amount: delta * config.scrollFollowGain)]
    }

    /// Rate control: distance from the neutral height sets speed. Nothing happens
    /// inside the dead zone; beyond it speed rises linearly to 1 at
    /// `scrollFullSpeedOffset` and stays there.
    private func rateScroll(for sample: HandSample, dt: Double) -> [GestureEvent] {
        let offset = sample.y - scrollNeutralY
        let magnitude = abs(offset)
        guard dt > 0, magnitude > config.scrollDeadZone else { return [] }

        let span = config.scrollFullSpeedOffset - config.scrollDeadZone
        let rate = min(1, (magnitude - config.scrollDeadZone) / span)
        return [.scroll(amount: (offset < 0 ? -rate : rate) * dt)]
    }

    // MARK: - Helpers

    /// Forget recent motion so stale positions cannot form a swipe or a scroll
    /// jump once the hand comes back.
    private func resetTracking() {
        window.removeAll()
        previousTime = nil
        followY = nil
    }

    private func disarm(_ reason: DisarmReason) -> [GestureEvent] {
        state = .idle
        holdAnchor = nil
        fistSince = nil
        lostSince = nil
        awaitingReturn = false
        mode = .other
        lastDisarmReason = reason
        resetTracking()
        return [.disarmed]
    }
}
