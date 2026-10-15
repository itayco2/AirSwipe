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
///     two fingers                  scroll mode: hand height scrolls
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
    // pose being considered for it, and the height scrolling is measured from.
    private var mode: HandPose = .other
    private var candidatePose: HandPose = .other
    private var candidateSince: TimeInterval = 0
    private var candidateY = 0.5
    private var scrollNeutralY = 0.5

    // Armed: tracking. Position is followed in every pose so that a swipe
    // survives a flicker; the mode only decides whether it counts.
    private var previousTime: TimeInterval?
    private var window: [(time: TimeInterval, x: Double, y: Double)] = []
    private var lastSwipeTime: TimeInterval = -.infinity

    // Armed: signals that lead to disarming.
    private var lastActivity: TimeInterval = 0
    private var fistSince: TimeInterval?
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
            return time - since >= config.handLostDisarmDuration ? disarm() : []
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
            return disarm()
        }

        updateMode(for: sample, at: time)

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

    /// A pose becomes the mode only after it has been steady for
    /// `poseStableDuration`. Entering scroll mode records the height it started
    /// at, which is what scrolling is then measured from.
    private func updateMode(for sample: HandSample, at time: TimeInterval) {
        if sample.pose != candidatePose {
            candidatePose = sample.pose
            candidateSince = time
            candidateY = sample.y
        }
        if mode != candidatePose, time - candidateSince >= config.poseStableDuration {
            mode = candidatePose
            if mode == config.scrollPose {
                scrollNeutralY = candidateY
            }
        }
    }

    private func gestureEvents(for sample: HandSample, at time: TimeInterval,
                               dt: Double) -> [GestureEvent] {
        if let direction = detectSwipe(sample, at: time) {
            return [.swipe(direction)]
        }
        guard mode == config.scrollPose else { return [] }
        return scroll(for: sample, dt: dt)
    }

    /// A swipe is a fast, mostly horizontal move across the recent window, made
    /// in swipe mode. After one fires, further swipes are suppressed for
    /// `swipeCooldown`, which is what swallows the hand's return stroke.
    private func detectSwipe(_ sample: HandSample, at time: TimeInterval) -> SwipeDirection? {
        window.append((time, sample.x, sample.y))
        window.removeAll { time - $0.time > config.swipeWindow }

        guard mode == config.swipePose,
              time - lastSwipeTime >= config.swipeCooldown,
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
    }

    private func disarm() -> [GestureEvent] {
        state = .idle
        holdAnchor = nil
        fistSince = nil
        lostSince = nil
        mode = .other
        resetTracking()
        return [.disarmed]
    }
}
