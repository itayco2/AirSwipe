import Foundation

/// Turns a stream of timestamped hand samples into gesture events.
///
/// The engine is a pure state machine: it never reads a clock or touches the
/// camera. Time comes only from the `time` argument, which is what makes the
/// hard part of this project (false positives) testable with synthetic input.
///
///     idle ──(open palm held still)──▶ armed ──(fist / hand lost / idle)──▶ idle
///
/// While armed it reports horizontal swipes and, from hand height, scrolling.
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
    /// Set after an idle timeout. The hand must leave or close before it can arm
    /// again; otherwise a palm still raised would re-arm at once and flap.
    private var needsRelease = false

    // Armed: the neutral height scrolling is measured from, the previous frame's
    // time (for integrating scroll), recent positions, and the last swipe.
    private var neutralY = 0.5
    private var previousTime: TimeInterval?
    private var window: [(time: TimeInterval, x: Double, y: Double)] = []
    private var lastSwipeTime: TimeInterval = -.infinity

    // Armed: signals that lead to disarming.
    private var lastActivity: TimeInterval = 0
    private var closedSince: TimeInterval?
    private var lostSince: TimeInterval?

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
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
    /// settled for `armHoldDuration`. Any movement past the radius, or a closed
    /// or missing hand, restarts the hold. The settled height becomes neutral.
    private func processIdle(_ sample: HandSample?, at time: TimeInterval) -> [GestureEvent] {
        guard let sample, sample.isOpen else {
            holdAnchor = nil
            needsRelease = false
            return []
        }
        if needsRelease { return [] }

        if let anchor = holdAnchor,
           hypot(sample.x - anchor.x, sample.y - anchor.y) <= config.armStillnessRadius {
            if time - holdStart >= config.armHoldDuration {
                state = .armed
                neutralY = anchor.y
                holdAnchor = nil
                lastActivity = time
                lastSwipeTime = -.infinity
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
        // No hand: ride out short dropouts, disarm after a sustained loss.
        guard let sample else {
            resetTracking()
            let since = lostSince ?? time
            lostSince = since
            return time - since >= config.handLostDisarmDuration ? disarm() : []
        }
        lostSince = nil

        // Whether the hand reads open flickers during fast motion, because fingers
        // curl and tilt mid-swipe. So it must not interrupt tracking: a closed
        // hand only pauses scrolling, and disarms once it has stayed closed for
        // `fistDisarmDuration`.
        if sample.isOpen {
            closedSince = nil
        } else {
            closedSince = closedSince ?? time
        }
        if let closedSince, time - closedSince >= config.fistDisarmDuration {
            return disarm()
        }

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
            return disarm()
        }
        return []
    }

    private func gestureEvents(for sample: HandSample, at time: TimeInterval,
                               dt: Double) -> [GestureEvent] {
        if let direction = detectSwipe(sample, at: time) {
            return [.swipe(direction)]
        }
        // Scrolling pauses while a swipe cools down so the hand's travel and
        // return stroke cannot drag the page, and while the hand reads closed.
        guard sample.isOpen, time - lastSwipeTime >= config.swipeCooldown else { return [] }
        return scroll(for: sample, dt: dt)
    }

    /// A swipe is a fast, mostly horizontal move across the recent window. After
    /// one fires, further swipes are suppressed for `swipeCooldown`, which is what
    /// swallows the hand's return stroke.
    private func detectSwipe(_ sample: HandSample, at time: TimeInterval) -> SwipeDirection? {
        window.append((time, sample.x, sample.y))
        window.removeAll { time - $0.time > config.swipeWindow }

        guard time - lastSwipeTime >= config.swipeCooldown,
              let oldest = window.first else {
            return nil
        }

        let dx = sample.x - oldest.x
        let dy = sample.y - oldest.y
        guard abs(dx) >= config.swipeMinDistance,
              abs(dy) <= config.swipeMaxVerticalRatio * abs(dx) else {
            return nil
        }

        lastSwipeTime = time
        window.removeAll()
        return dx > 0 ? .right : .left
    }

    /// Rate control: distance from the neutral height sets speed. Nothing happens
    /// inside the dead zone; beyond it speed rises linearly to 1 at
    /// `scrollFullSpeedOffset` and stays there.
    private func scroll(for sample: HandSample, dt: Double) -> [GestureEvent] {
        let offset = sample.y - neutralY
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
    }

    private func disarm() -> [GestureEvent] {
        state = .idle
        holdAnchor = nil
        closedSince = nil
        lostSince = nil
        resetTracking()
        return [.disarmed]
    }
}
