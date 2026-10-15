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
///     one finger                   stroke mode: a quick sideways move swipes,
///                                  a quick up or down move flicks
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

    private enum Axis {
        case horizontal
        case vertical
    }

    private enum Stroke {
        case swipe(SwipeDirection)
        case flick(FlickDirection)
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

    // Armed: tracking. Position is followed in every pose so that a stroke
    // survives a flicker; the mode only decides whether it counts.
    private var previousTime: TimeInterval?
    private var window: [(time: TimeInterval, x: Double, y: Double)] = []
    private var lastStrokeTime: TimeInterval = -.infinity

    // Armed: the return guard. After a stroke the hand comes back toward where it
    // started, and that return must not count as a stroke the other way. Positions
    // are measured along the axis the stroke used. `returnDirection` is +1 for a
    // stroke that went right or up and -1 for one that went left or down.
    private var awaitingReturn = false
    private var returnAxis: Axis = .horizontal
    private var returnDirection = 1.0
    private var returnHome = 0.5
    private var guardSince: TimeInterval = 0
    private var dwellValue = 0.5
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
        let axisName = returnAxis == .horizontal ? "x" : "y"
        let guardText = awaitingReturn ? String(format: "ON(%@=%.2f)", axisName, returnHome) : "off"
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
                lastStrokeTime = -.infinity
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

    private func value(_ axis: Axis, x: Double, y: Double) -> Double {
        axis == .horizontal ? x : y
    }

    private func minDistance(for axis: Axis) -> Double {
        axis == .horizontal ? config.swipeMinDistance : config.flickMinDistance
    }

    /// While a stroke's return is pending, watch for the hand to come back. The
    /// guard lifts when the hand has arrived back where the stroke started and has
    /// turned around or slowed, so a stroke that follows without a pause is tracked
    /// while a return that overshoots is not. It also lifts when the hand settles a
    /// little short of that point, when it has rested anywhere for a while, or on
    /// its own after `swipeReturnGuard`, so it can never leave strokes stuck off.
    private func updateReturnGuard(for sample: HandSample, at time: TimeInterval) {
        guard awaitingReturn else { return }

        let homeRadius = returnAxis == .horizontal ? config.swipeHomeRadius : config.flickHomeRadius
        let settleRadius = returnAxis == .horizontal ? config.swipeSettleRadius : config.flickSettleRadius

        let current = value(returnAxis, x: sample.x, y: sample.y)
        if abs(current - dwellValue) > config.swipeDwellRadius {
            dwellValue = current
            dwellSince = time
        }
        let dwell = time - dwellSince

        // Back at the start point, and either turning around or slowing down. A
        // return that overshoots does neither until it is well past it.
        let atHome = abs(current - returnHome) <= homeRadius
        var turnedAround = false
        if window.count >= 2 {
            let last = value(returnAxis, x: window[window.count - 1].x, y: window[window.count - 1].y)
            let before = value(returnAxis, x: window[window.count - 2].x, y: window[window.count - 2].y)
            turnedAround = (last - before) * (current - last) < 0
        }
        let arrivedHome = atHome && (turnedAround || isSlow(at: time, current: current))

        let settledNearHome = abs(dwellValue - returnHome) <= settleRadius
            && dwell >= config.swipeSettleDwell
        let restedAway = dwell >= config.swipeRestDuration
        let expired = time - guardSince >= config.swipeReturnGuard

        if arrivedHome || settledNearHome || restedAway || expired {
            awaitingReturn = false
            // The window still holds the return stroke. Left in place it would
            // fire the instant the guard lifts. Keep only the last stretch, which
            // is the slow turnaround a new stroke starts from.
            window.removeAll { time - $0.time > config.swipeSlowWindow }
        }
    }

    /// True once the hand has (nearly) stopped along the guarded axis: it moved
    /// little over the last `swipeSlowWindow` seconds. Needs that much history,
    /// and is false without it.
    private func isSlow(at time: TimeInterval, current: Double) -> Bool {
        guard let reference = window.last(where: { time - $0.time >= config.swipeSlowWindow }) else {
            return false
        }
        let before = value(returnAxis, x: reference.x, y: reference.y)
        return abs(current - before) / (time - reference.time) <= config.swipeSlowSpeed
    }

    private func gestureEvents(for sample: HandSample, at time: TimeInterval,
                               dt: Double) -> [GestureEvent] {
        if let stroke = detectStroke(sample, at: time) {
            switch stroke {
            case .swipe(let direction): return [.swipe(direction)]
            case .flick(let direction): return [.flick(direction)]
            }
        }
        guard mode == config.scrollPose else { return [] }
        return scroll(for: sample, dt: dt)
    }

    /// A stroke is a fast, mostly straight move made in stroke mode, sideways for a
    /// swipe or up and down for a flick. Its travel is measured from the turnaround
    /// point in the recent window, not from the oldest sample, so a stroke straight
    /// after a return keeps the distance the hand covered on its way back. A move
    /// that is diagonal is neither.
    ///
    /// After a stroke fires, the next one waits for the hand to return (see
    /// `updateReturnGuard`), which keeps the move back from counting the other way.
    /// The one exception is a *carry-on*: a move the other way that goes a full
    /// stroke past where the previous one began. That is deliberate, not a return,
    /// and it is what lets an up-and-down or side-to-side bounce work.
    private func detectStroke(_ sample: HandSample, at time: TimeInterval) -> Stroke? {
        window.append((time, sample.x, sample.y))
        window.removeAll { time - $0.time > config.swipeWindow }

        guard mode == config.swipePose,
              let lowX = window.min(by: { $0.x < $1.x }),
              let highX = window.max(by: { $0.x < $1.x }),
              let lowY = window.min(by: { $0.y < $1.y }),
              let highY = window.max(by: { $0.y < $1.y }) else {
            return nil
        }

        // Sideways.
        let rightward = sample.x - lowX.x
        let leftward = highX.x - sample.x
        let goesRight = rightward >= leftward
        let travelX = goesRight ? rightward : leftward
        let originX = goesRight ? lowX : highX
        let isSideways = travelX >= config.swipeMinDistance
            && abs(sample.y - originX.y) <= config.swipeMaxVerticalRatio * travelX

        // Up and down.
        let upward = sample.y - lowY.y
        let downward = highY.y - sample.y
        let goesUp = upward >= downward
        let travelY = goesUp ? upward : downward
        let originY = goesUp ? lowY : highY
        let isVertical = travelY >= config.flickMinDistance
            && abs(sample.x - originY.x) <= config.swipeMaxVerticalRatio * travelY

        let axis: Axis
        switch (isSideways, isVertical) {
        case (false, false): return nil
        case (true, false): axis = .horizontal
        case (false, true): axis = .vertical
        case (true, true):
            let sidewaysShare = travelX / config.swipeMinDistance
            let verticalShare = travelY / config.flickMinDistance
            axis = sidewaysShare >= verticalShare ? .horizontal : .vertical
        }

        let isPositive = axis == .horizontal ? goesRight : goesUp
        let direction = isPositive ? 1.0 : -1.0
        let current = value(axis, x: sample.x, y: sample.y)

        var isCarryOn = false
        if awaitingReturn {
            // Only a carry-on counts while a return is pending: same axis, the
            // opposite way, and a full stroke past where the previous one began.
            guard axis == returnAxis, direction == -returnDirection,
                  (returnHome - current) * returnDirection >= minDistance(for: axis) else {
                return nil
            }
            isCarryOn = true
        } else if time - lastStrokeTime < config.swipeCooldown {
            return nil
        }

        lastStrokeTime = time
        awaitingReturn = true
        returnAxis = axis
        returnDirection = direction
        if !isCarryOn {
            // A carry-on keeps the earlier start point as home, so a bounce stays
            // centred on the middle instead of drifting toward each extreme.
            returnHome = axis == .horizontal ? originX.x : originY.y
        }
        guardSince = time
        dwellValue = current
        dwellSince = time
        window.removeAll()

        if axis == .horizontal {
            return .swipe(goesRight ? .right : .left)
        }
        return .flick(goesUp ? .up : .down)
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

    /// Forget recent motion so stale positions cannot form a stroke or a scroll
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
