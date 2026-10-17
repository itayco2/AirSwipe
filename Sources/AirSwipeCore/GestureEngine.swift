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
///     thumb and index tips touching  pinch scroll: the page follows the hand up and
///                                  down; opening the pinch lets go (checked first)
///     one finger                   stroke mode: a quick sideways move swipes
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
    private var candidateX = 0.5
    private var candidateY = 0.5
    /// The last time the swipe pose was read, however briefly, for `strokePoseHold`.
    private var lastSwipePoseTime: TimeInterval = -.infinity
    /// The last time an open palm was read, however briefly, for palm mode's hold.
    private var lastPalmPoseTime: TimeInterval = -.infinity
    private var circle: CircleDetector
    private var scrollNeutralY = 0.5
    /// Smoothed hand height while the page is following the hand.
    private var followY: Double?

    // Armed: tracking. Position is followed in every pose so that a swipe
    // survives a flicker; the mode only decides whether it counts.
    private var previousTime: TimeInterval?
    private var window: [(time: TimeInterval, x: Double, y: Double)] = []
    private var lastStrokeTime: TimeInterval = -.infinity

    // Armed: the return guard, for swipes. After a swipe the hand comes back toward where
    // it started, and that return must not count as a swipe the other way. Positions are
    // x. `returnDirection` is +1 for a swipe that went right and -1 for one that went left.
    private var awaitingReturn = false
    private var returnDirection = 1.0
    private var returnHome = 0.5
    private var guardSince: TimeInterval = 0
    private var dwellValue = 0.5
    private var dwellSince: TimeInterval = 0

    // Armed: pinch scroll. Fingertips touching grab the page and the hand drags it.
    private var pinchScroller: PinchScroller

    // Armed: signals that lead to disarming.
    private var lastActivity: TimeInterval = 0
    private var fistSince: TimeInterval?
    /// Where the current fist started, so a fist that is travelling can be told from
    /// one that is held still.
    private var fistAnchor: (x: Double, y: Double)?
    private var lostSince: TimeInterval?

    // Armed: a thumbs up being held, which sends once per hold.
    private var thumbSince: TimeInterval?
    private var thumbAnchor: (x: Double, y: Double)?
    private var lastThumbTime: TimeInterval = -.infinity
    /// True once this hold has sent, until the thumb comes down.
    private var thumbLatched = false

    /// Why the engine most recently disarmed, so the app can explain it.
    public private(set) var lastDisarmReason: DisarmReason?

    /// For debugging: set when the latest frame held a move big enough to be a
    /// stroke that was not accepted, with the reason and the numbers behind it.
    /// It is nil on any frame where nothing was turned down.
    public private(set) var lastRejection: String?

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
        self.circle = CircleDetector(config: config)
        self.pinchScroller = PinchScroller(config: config)
    }

    /// Whether the engine is listening: it was armed by an open palm and has not stopped.
    public var isArmed: Bool { state == .armed }

    /// The pose that currently decides what a movement means (only meaningful while armed).
    public var currentMode: HandPose { mode }

    /// Whether a pinch is holding the page right now, so the hand is scrolling it.
    public var isGrabbing: Bool { pinchScroller.isEngaged }

    /// One line describing the engine's internal state, for debugging.
    public var diagnostics: String {
        let guardText = awaitingReturn ? String(format: "ON(x=%.2f)", returnHome) : "off"
        return "mode=\(mode) guard=\(guardText) grab=\(pinchScroller.isEngaged ? "ON" : "off")"
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
                lastPalmPoseTime = time
                candidatePose = .openPalm
                candidateSince = time
                candidateX = sample.x
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

        // A pinch comes first. Fingertips touching are a finger on the glass: while they are,
        // the pose readings mean nothing (a pinch with curled fingers reads as a fist or a
        // thumbs up) and neither does the hand's movement (it is the scroll, not a swipe).
        let pinch = pinchScroller.update(pinch: sample.pinch, y: sample.y, at: time)
        if pinch.isActive {
            fistSince = nil
            fistAnchor = nil
            thumbSince = nil
            thumbAnchor = nil
            thumbLatched = false
            window.removeAll()
            circle.reset()
            lastRejection = nil
            if pinch.isEngaged { lastActivity = time }
            return pinch.scroll == 0 ? [] : [.scroll(amount: pinch.scroll)]
        }
        if pinch.released {
            // Letting go moves the hand too. That move is not a swipe.
            window.removeAll()
        }

        // A fist is the stop signal, and only a fist: a pose that is merely
        // in-between never disarms. It must persist, because fingers curl for a
        // moment during fast movement, and it must be held still, because a hand
        // moving low in the frame often reads as a fist: a travelling fist restarts
        // the clock, the way a palm that moves restarts arming.
        if sample.pose == .fist {
            if let anchor = fistAnchor, fistSince != nil,
               hypot(sample.x - anchor.x, sample.y - anchor.y) <= config.fistStillnessRadius {
                // Still holding: keep the clock running.
            } else {
                fistSince = time
                fistAnchor = (sample.x, sample.y)
            }
        } else {
            fistSince = nil
            fistAnchor = nil
        }
        if let fistSince, time - fistSince >= config.fistDisarmDuration {
            return disarm(.fist)
        }

        if let events = sendEvents(for: sample, at: time) {
            lastActivity = time
            return events
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

    /// A thumbs up held still for `sendHoldDuration` sends, once per hold: the thumb has
    /// to come down before it can send again. A reading of `other` or `fist` in the
    /// middle of a hold is forgiven for `sendGrace`, since the thumb is the joint set the
    /// camera reads least reliably; any other clear pose ends the hold at once. Returns
    /// nil when there is nothing to report.
    private func sendEvents(for sample: HandSample, at time: TimeInterval) -> [GestureEvent]? {
        guard config.sendEnabled else { return nil }

        if sample.pose == .thumbsUp {
            lastThumbTime = time
            if let anchor = thumbAnchor, thumbSince != nil,
               hypot(sample.x - anchor.x, sample.y - anchor.y) <= config.sendStillnessRadius {
                // Still holding it: keep the clock running.
            } else {
                thumbSince = time
                thumbAnchor = (sample.x, sample.y)
            }
            if !thumbLatched, let since = thumbSince, time - since >= config.sendHoldDuration {
                thumbLatched = true
                return [.send]
            }
            return nil
        }

        let unclear = sample.pose == .other || sample.pose == .fist
        if unclear, time - lastThumbTime <= config.sendGrace { return nil }
        thumbSince = nil
        thumbAnchor = nil
        thumbLatched = false
        return nil
    }

    /// A pose becomes the mode only after it has been steady for
    /// `poseStableDuration`. Entering scroll mode records the height it started
    /// at, which `.rate` scrolling is measured from.
    ///
    /// Stroke mode and palm mode are stickier. A reading that is merely unclear
    /// (`.other`, `.fist`) does not end them and cancels any switch that was pending,
    /// because with the hand low in the frame or moving fast the pose reads that way
    /// most of the time even though the same pose is still being shown. The mode ends
    /// when a clear different pose has been steady, or when `strokePoseHold` has passed
    /// with no reading of its own pose.
    private func updateMode(for sample: HandSample, at time: TimeInterval) {
        if sample.pose == config.swipePose {
            lastSwipePoseTime = time
        }
        if sample.pose == .openPalm {
            lastPalmPoseTime = time
        }
        let isUnclear = sample.pose == .other || sample.pose == .fist
        if isUnclear, mode == config.swipePose || mode == .openPalm {
            candidatePose = mode
            candidateSince = time
            candidateX = sample.x
            candidateY = sample.y
            let lastClear = mode == .openPalm ? lastPalmPoseTime : lastSwipePoseTime
            if time - lastClear >= config.strokePoseHold {
                mode = .other
                candidatePose = .other
            }
            return
        }

        if sample.pose != candidatePose {
            candidatePose = sample.pose
            candidateSince = time
            candidateX = sample.x
            candidateY = sample.y
        } else if mode != candidatePose, candidatePose == config.swipePose,
                  hypot(sample.x - candidateX, sample.y - candidateY) > config.poseStableRadius {
            // The hand moved while one finger was showing: a moving hand is not a change to
            // swipe mode on purpose (one finger is what a camera misreads in a moving hand,
            // and a swipe is what that would fire). Start counting again from here. Other
            // poses are not held to this: an open palm must take over at once.
            candidateSince = time
            candidateX = sample.x
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
    /// guard lifts when the hand has arrived back where the swipe started and has
    /// turned around or slowed, so a swipe that follows without a pause is tracked
    /// while a return that overshoots is not. It also lifts when the hand settles a
    /// little short of that point, when it has rested anywhere for a while, or on
    /// its own after `swipeReturnGuard`, so it can never leave swipes stuck off.
    private func updateReturnGuard(for sample: HandSample, at time: TimeInterval) {
        guard awaitingReturn else { return }

        let current = sample.x
        if abs(current - dwellValue) > config.swipeDwellRadius {
            dwellValue = current
            dwellSince = time
        }
        let dwell = time - dwellSince

        // Back at the start point, and either turning around or slowing down. A
        // return that overshoots does neither until it is well past it.
        let atHome = abs(current - returnHome) <= config.swipeHomeRadius
        var turnedAround = false
        if window.count >= 2 {
            let last = window[window.count - 1].x
            let before = window[window.count - 2].x
            turnedAround = (last - before) * (current - last) < 0
        }
        let arrivedHome = atHome && (turnedAround || isSlow(at: time, current: current))

        let settledNearHome = abs(dwellValue - returnHome) <= config.swipeSettleRadius
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

    /// True once the hand has (nearly) stopped sideways: it moved little over the last
    /// `swipeSlowWindow` seconds. Needs that much history, and is false without it.
    private func isSlow(at time: TimeInterval, current: Double) -> Bool {
        guard let reference = window.last(where: { time - $0.time >= config.swipeSlowWindow }) else {
            return false
        }
        return abs(current - reference.x) / (time - reference.time) <= config.swipeSlowSpeed
    }

    private func gestureEvents(for sample: HandSample, at time: TimeInterval,
                               dt: Double) -> [GestureEvent] {
        if let direction = detectSwipe(sample, at: time) {
            return [.swipe(direction)]
        }
        if config.circleEnabled {
            // An open palm showing counts even if the mode has not caught up with it yet, so a
            // circle that starts right after a swipe is not missing its first stretch.
            if mode == .openPalm || sample.pose == .openPalm {
                if circle.add(x: sample.x, y: sample.y, at: time) {
                    return [.circle]
                }
            } else {
                circle.reset()
            }
        }
        guard mode == config.scrollPose else { return [] }
        return scroll(for: sample, dt: dt)
    }

    /// A swipe is a fast, mostly sideways move made in one-finger mode. A move that is
    /// diagonal is not one. (Scrolling is the pinch, see `PinchScroller`: the up and down
    /// flick that used to be here could not tell a flick from the hand coming back.)
    ///
    /// The travel is measured from the turnaround point in the recent window, so a swipe
    /// straight after a return keeps the distance the hand covered on its way back. After a
    /// swipe fires, the next waits for the hand to return (see `updateReturnGuard`), which
    /// keeps the move back from counting the other way. The one exception is a *carry-on*:
    /// a move the other way that goes a full swipe past where the previous one began. That
    /// is deliberate, not a return, and it lets a side-to-side bounce work.
    private func detectSwipe(_ sample: HandSample, at time: TimeInterval) -> SwipeDirection? {
        lastRejection = nil
        window.append((time, sample.x, sample.y))
        window.removeAll { time - $0.time > config.swipeWindow }

        guard let lowX = window.min(by: { $0.x < $1.x }),
              let highX = window.max(by: { $0.x < $1.x }) else {
            return nil
        }

        let rightward = sample.x - lowX.x
        let leftward = highX.x - sample.x
        let goesRight = rightward >= leftward
        let travelX = goesRight ? rightward : leftward
        let originX = goesRight ? lowX : highX
        let vertical = abs(sample.y - originX.y)
        guard travelX >= config.swipeMinDistance else { return nil }
        guard vertical <= config.swipeMaxVerticalRatio * travelX else {
            lastRejection = String(format: "diagonal: across %.2f, up/down %.2f, too far off the axis",
                                   travelX, vertical)
            return nil
        }

        let direction = goesRight ? 1.0 : -1.0
        let name = goesRight ? "right" : "left"
        let travel = travelX

        // A move turned down below is forgotten, not postponed: left in the window it would
        // fire as a swipe the moment the reason for turning it down went away (the mode
        // catching up, the palm guard running out).
        guard mode == config.swipePose else {
            lastRejection = String(format: "%@ %.2f ignored: mode is %@, not %@ (pose now %@)",
                                   name, travel, "\(mode)", "\(config.swipePose)", "\(sample.pose)")
            window.removeAll()
            return nil
        }
        // A swipe is made with one finger. An open palm showing a moment ago means this is a
        // circle or a wave, even if the mode has not caught up with the palm yet.
        guard time - lastPalmPoseTime >= config.swipePalmGuard else {
            lastRejection = String(format: "%@ %.2f ignored: an open palm was showing %.2fs ago, a swipe is made with one finger",
                                   name, travel, time - lastPalmPoseTime)
            window.removeAll()
            return nil
        }

        let current = sample.x
        var isCarryOn = false
        if awaitingReturn {
            // Only a carry-on counts while a return is pending: the opposite way, and a
            // full swipe past where the previous one began.
            let pastHome = (returnHome - current) * returnDirection
            guard direction == -returnDirection, pastHome >= config.swipeMinDistance else {
                if direction == returnDirection {
                    lastRejection = String(format: "%@ %.2f held: same way as the last stroke", name, travel)
                } else {
                    lastRejection = String(format: "%@ %.2f held by return guard: %.2f past home %.2f, needs %.2f",
                                           name, travel, pastHome, returnHome, config.swipeMinDistance)
                }
                return nil
            }
            isCarryOn = true
        } else if time - lastStrokeTime < config.swipeCooldown {
            lastRejection = String(format: "%@ %.2f held by cooldown, %.2fs left", name, travel,
                                   config.swipeCooldown - (time - lastStrokeTime))
            return nil
        }

        lastStrokeTime = time
        awaitingReturn = true
        returnDirection = direction
        if !isCarryOn {
            // A carry-on keeps the earlier start point as home, so a bounce stays
            // centred on the middle instead of drifting toward each extreme.
            returnHome = originX.x
        }
        guardSince = time
        dwellValue = current
        dwellSince = time
        window.removeAll()

        return goesRight ? .right : .left
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
        circle.reset()
        pinchScroller.reset()
        thumbSince = nil
        thumbAnchor = nil
        thumbLatched = false
        lastRejection = nil
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
