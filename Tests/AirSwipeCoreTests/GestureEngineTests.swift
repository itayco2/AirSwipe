import Foundation
import Testing
import AirSwipeCore

/// Feeds synthetic hand samples to an engine at a fixed frame rate and returns
/// the events each segment produced, so tests read like a script of hand movement.
struct Rig {
    let engine: GestureEngine
    let fps = 30.0
    private(set) var time = 0.0
    private(set) var x = 0.5
    private(set) var y = 0.5
    /// The pose shown by `hold` and `move` unless one is passed explicitly.
    var pose: HandPose = .openPalm
    /// The pinch reading sent with every frame (nil: the camera could not read it).
    var pinch: Double?

    init(config: GestureConfig = GestureConfig()) {
        engine = GestureEngine(config: config)
    }

    /// Keep the hand where it is (or at an explicit spot) for `seconds`.
    @discardableResult
    mutating func hold(x newX: Double? = nil, y newY: Double? = nil,
                       for seconds: Double, pose override: HandPose? = nil) -> [GestureEvent] {
        move(toX: newX ?? x, toY: newY ?? y, over: seconds, pose: override)
    }

    /// Glide in a straight line to (toX, toY) over `seconds`.
    @discardableResult
    mutating func move(toX: Double, toY: Double, over seconds: Double,
                       pose override: HandPose? = nil) -> [GestureEvent] {
        let shown = override ?? pose
        let frames = max(1, Int((seconds * fps).rounded()))
        let (startX, startY) = (x, y)
        var events: [GestureEvent] = []
        for frame in 1...frames {
            let t = Double(frame) / Double(frames)
            x = startX + (toX - startX) * t
            y = startY + (toY - startY) * t
            time += 1 / fps
            events += engine.process(HandSample(x: x, y: y, pose: shown, pinch: pinch), at: time)
        }
        return events
    }

    /// No hand visible for `seconds`.
    @discardableResult
    mutating func noHand(for seconds: Double) -> [GestureEvent] {
        let frames = max(1, Int((seconds * fps).rounded()))
        var events: [GestureEvent] = []
        for _ in 1...frames {
            time += 1 / fps
            events += engine.process(nil, at: time)
        }
        return events
    }

    /// Switch to `newPose` in place and hold it long enough to become the mode.
    @discardableResult
    mutating func show(_ newPose: HandPose) -> [GestureEvent] {
        pose = newPose
        return hold(for: 0.3)
    }
}

extension Rig {
    /// Armed, with an open palm resting mid-frame.
    static func armed(config: GestureConfig = GestureConfig()) -> Rig {
        var rig = Rig(config: config)
        rig.hold(for: 0.8)
        return rig
    }

    /// Armed and showing one finger: swipe mode.
    static func swiping(config: GestureConfig = GestureConfig()) -> Rig {
        var rig = armed(config: config)
        rig.show(.oneFinger)
        return rig
    }

    /// Armed and showing two fingers: scroll mode, neutral at mid-frame.
    static func scrolling(config: GestureConfig = GestureConfig()) -> Rig {
        var rig = armed(config: config)
        rig.show(.twoFingers)
        return rig
    }
}

/// Only the swipe events, so a test can ignore anything else a move also causes.
private func swipes(in events: [GestureEvent]) -> [GestureEvent] {
    events.filter {
        if case .swipe = $0 { return true }
        return false
    }
}

/// Only the scroll amounts, in order.
private func scrolls(in events: [GestureEvent]) -> [Double] {
    events.compactMap {
        if case .scroll(let amount) = $0 { return amount }
        return nil
    }
}

// MARK: - Arming

@Suite("Arming")
struct ArmingTests {
    @Test("an open palm held still arms the engine")
    func armsAfterStillOpenPalm() {
        var rig = Rig()
        let events = rig.hold(for: 0.8)
        #expect(events == [.armed])
    }

    @Test("nothing happens before the full hold duration has passed")
    func notArmedBeforeHoldDuration() {
        var rig = Rig()
        let tooShort = rig.hold(for: 0.4)
        #expect(tooShort.isEmpty)
        let rest = rig.hold(for: 0.3)
        #expect(rest == [.armed])
    }

    @Test("waving does not arm until the hand is held still")
    func wavingDoesNotArm() {
        var rig = Rig()
        var waving: [GestureEvent] = []
        for _ in 0..<3 {
            waving += rig.move(toX: 0.65, toY: 0.5, over: 0.25)
            waving += rig.move(toX: 0.35, toY: 0.5, over: 0.25)
        }
        #expect(waving.isEmpty)
        let settled = rig.hold(for: 0.8)
        #expect(settled == [.armed])
    }

    @Test("a fist never arms, even held still")
    func fistDoesNotArm() {
        var rig = Rig()
        let fist = rig.hold(for: 1.0, pose: .fist)
        #expect(fist.isEmpty)
        let open = rig.hold(for: 0.8)
        #expect(open == [.armed])
    }

    @Test("only an open palm arms: one or two fingers do not")
    func fingersDoNotArm() {
        var rig = Rig()
        #expect(rig.hold(for: 1.0, pose: .oneFinger).isEmpty)
        #expect(rig.hold(for: 1.0, pose: .twoFingers).isEmpty)
        #expect(rig.hold(for: 0.8) == [.armed])
    }
}

// MARK: - Swipe

@Suite("Swipe")
struct SwipeTests {
    @Test("a fast move to the right with one finger emits swipe right")
    func swipeRight() {
        var rig = Rig.swiping()
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: events) == [.swipe(.right)])
    }

    @Test("a fast move to the left with one finger emits swipe left")
    func swipeLeft() {
        var rig = Rig.swiping()
        let events = rig.move(toX: 0.20, toY: 0.5, over: 0.2)
        #expect(swipes(in: events) == [.swipe(.left)])
    }

    @Test("a fast move while not armed does nothing, and arming still works afterward")
    func notArmedNoSwipe() {
        var rig = Rig()
        rig.pose = .oneFinger
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(events.isEmpty)
        rig.pose = .openPalm
        let settled = rig.hold(for: 0.8)
        #expect(settled == [.armed])
    }

    @Test("an open palm moving fast does not swipe, but one finger does")
    func openPalmDoesNotSwipe() {
        var rig = Rig.armed()
        let palm = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: palm).isEmpty)
        rig.hold(for: 0.5)
        rig.show(.oneFinger)
        let finger = rig.move(toX: 0.40, toY: 0.5, over: 0.2)
        #expect(swipes(in: finger) == [.swipe(.left)])
    }

    @Test("two fingers moving sideways do not swipe, but one finger does")
    func twoFingersDoNotSwipe() {
        var rig = Rig.scrolling()
        let sideways = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: sideways).isEmpty)
        rig.hold(for: 0.5)
        rig.show(.oneFinger)
        let finger = rig.move(toX: 0.40, toY: 0.5, over: 0.2)
        #expect(swipes(in: finger) == [.swipe(.left)])
    }

    // A mostly vertical move is never a swipe (scrolling is the pinch), and swiping works
    // again once the hand has come back.
    @Test("a mostly vertical move is not a swipe, and swiping works after the return")
    func verticalMoveIsNotASwipe() {
        var rig = Rig.swiping()
        let vertical = rig.move(toX: 0.70, toY: 0.90, over: 0.2)
        #expect(swipes(in: vertical).isEmpty)
        rig.hold(for: 0.5)
        rig.move(toX: 0.50, toY: 0.50, over: 0.25)
        rig.hold(for: 0.5)
        let real = rig.move(toX: 0.20, toY: 0.50, over: 0.2)
        #expect(swipes(in: real) == [.swipe(.left)])
    }

    @Test("a sideways bounce: right, then carry on left past the middle")
    func sidewaysBounce() {
        var rig = Rig.swiping()
        var events: [GestureEvent] = []
        events += rig.move(toX: 0.75, toY: 0.5, over: 0.25)
        events += rig.move(toX: 0.25, toY: 0.5, over: 0.40)
        #expect(swipes(in: events) == [.swipe(.right), .swipe(.left)])
    }

    @Test("a slow drift is not a swipe, but a quick move afterward is")
    func slowDriftIgnored() {
        var rig = Rig.swiping()
        let drift = rig.move(toX: 0.90, toY: 0.5, over: 2.0)
        #expect(swipes(in: drift).isEmpty)
        let quick = rig.move(toX: 0.50, toY: 0.5, over: 0.2)
        #expect(swipes(in: quick) == [.swipe(.left)])
    }

    @Test("the return stroke right after a swipe is ignored; a later deliberate swipe fires")
    func returnStrokeIgnored() {
        var rig = Rig.swiping()
        let first = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: first) == [.swipe(.right)])
        let back = rig.move(toX: 0.50, toY: 0.5, over: 0.2)
        #expect(swipes(in: back).isEmpty)
        rig.hold(for: 0.8)
        let second = rig.move(toX: 0.20, toY: 0.5, over: 0.2)
        #expect(swipes(in: second) == [.swipe(.left)])
    }

    // User report: bringing the hand back to the middle swiped the other way.
    @Test("returning to the middle after a pause is not a swipe")
    func returnToMiddleIsNotASwipe() {
        var rig = Rig.swiping()
        let first = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: first) == [.swipe(.right)])
        rig.hold(for: 1.0)
        let back = rig.move(toX: 0.50, toY: 0.5, over: 0.25)
        #expect(swipes(in: back).isEmpty)
    }

    // Found by instrumenting the sequence test: the blocked return stroke was still
    // in the swipe window, so it fired the moment the hand settled and the guard lifted.
    @Test("settling in the middle after the return does not swipe by itself")
    func settlingDoesNotReleaseTheReturnAsASwipe() {
        var rig = Rig.swiping()
        rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        rig.hold(for: 1.0)
        rig.move(toX: 0.50, toY: 0.5, over: 0.25)
        let settled = rig.hold(for: 1.0)
        #expect(swipes(in: settled).isEmpty)
    }

    @Test("a return that slightly overshoots the middle is not a swipe either")
    func overshootingReturnIsNotASwipe() {
        var rig = Rig.swiping()
        rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        rig.hold(for: 1.0)
        let back = rig.move(toX: 0.44, toY: 0.5, over: 0.25)
        #expect(swipes(in: back).isEmpty)
    }

    // User report: after returning to the middle the next swipe was not tracked,
    // because the guard waited for a pause the hand never made.
    @Test("a swipe that follows the return without any pause is tracked")
    func swipeStraightAfterReturnIsTracked() {
        var rig = Rig.swiping()
        var events: [GestureEvent] = []
        events += rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        events += rig.hold(for: 0.5)
        events += rig.move(toX: 0.50, toY: 0.5, over: 0.25)
        events += rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: events) == [.swipe(.right), .swipe(.right)])
    }

    @Test("once the hand has settled in the middle, swipes work in both directions again")
    func swipesWorkAfterSettlingInTheMiddle() {
        var rig = Rig.swiping()
        var events: [GestureEvent] = []
        // Right, back to the middle, right again, back to the middle, then left.
        // A return that leaked through as a swipe would show up as an extra left.
        events += rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        events += rig.hold(for: 1.0)
        events += rig.move(toX: 0.50, toY: 0.5, over: 0.25)
        events += rig.hold(for: 0.9)
        events += rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        events += rig.hold(for: 1.0)
        events += rig.move(toX: 0.50, toY: 0.5, over: 0.25)
        events += rig.hold(for: 0.9)
        events += rig.move(toX: 0.20, toY: 0.5, over: 0.2)
        #expect(swipes(in: events) == [.swipe(.right), .swipe(.right), .swipe(.left)])
    }

    @Test("resting away from the middle for a moment lets swipes work from there")
    func restingAwayLiftsTheReturnGuard() {
        var rig = Rig.swiping()
        rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        rig.hold(for: 2.0)
        let swipe = rig.move(toX: 0.50, toY: 0.5, over: 0.2)
        #expect(swipes(in: swipe) == [.swipe(.left)])
    }

    @Test("the return guard expires on its own even if the hand keeps moving")
    func returnGuardExpires() {
        var rig = Rig.swiping()
        rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        for _ in 0..<4 {
            rig.move(toX: 0.76, toY: 0.5, over: 0.4)
            rig.move(toX: 0.84, toY: 0.5, over: 0.4)
        }
        let swipe = rig.move(toX: 0.56, toY: 0.5, over: 0.2)
        #expect(swipes(in: swipe) == [.swipe(.left)])
    }

    // Field evidence: natural swipes were about 0.14-0.16 of the frame wide, just
    // under the old 0.18 threshold, so only the big ones were tracked.
    @Test("a small, natural swipe is tracked")
    func smallSwipeIsTracked() {
        var rig = Rig.swiping()
        let right = rig.move(toX: 0.64, toY: 0.5, over: 0.25)
        #expect(swipes(in: right) == [.swipe(.right)])
    }

    // Measuring a swipe from the oldest sample in the window loses the distance the
    // hand covered on its way back to the middle; it has to be measured from the
    // turnaround point, or a small swipe straight after a return is missed.
    @Test("small swipes and small returns work as a sequence, with no pause")
    func smallSwipesInSequence() {
        var rig = Rig.swiping()
        var events: [GestureEvent] = []
        events += rig.move(toX: 0.64, toY: 0.5, over: 0.25)
        events += rig.hold(for: 0.5)
        events += rig.move(toX: 0.50, toY: 0.5, over: 0.25)
        events += rig.move(toX: 0.64, toY: 0.5, over: 0.25)
        events += rig.hold(for: 0.5)
        events += rig.move(toX: 0.50, toY: 0.5, over: 0.25)
        events += rig.hold(for: 0.5)
        events += rig.move(toX: 0.36, toY: 0.5, over: 0.25)
        #expect(swipes(in: events) == [.swipe(.right), .swipe(.right), .swipe(.left)])
    }

    // Field evidence: during a fast swipe the fingers curl or tilt, so the pose
    // reads as something else for a few frames. That must not cancel the swipe.
    @Test("a pose flicker in the middle of a swipe does not cancel it")
    func poseFlickerKeepsSwipe() {
        var rig = Rig.swiping()
        var events: [GestureEvent] = []
        events += rig.move(toX: 0.60, toY: 0.5, over: 0.067)
        events += rig.move(toX: 0.70, toY: 0.5, over: 0.067, pose: .other)
        events += rig.move(toX: 0.80, toY: 0.5, over: 0.067)
        #expect(events == [.swipe(.right)])
    }

    @Test("a pose must be steady before it changes the mode")
    func glimpseOfOneFingerIsIgnored() {
        var rig = Rig.armed()
        rig.hold(for: 0.1, pose: .oneFinger)
        let moving = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: moving).isEmpty)
        rig.hold(for: 0.5)
        rig.show(.oneFinger)
        let steady = rig.move(toX: 0.40, toY: 0.5, over: 0.2)
        #expect(swipes(in: steady) == [.swipe(.left)])
    }
}

// MARK: - Scroll

@Suite("Scroll")
struct ScrollTests {
    @Test("raising two fingers past the dead zone scrolls up")
    func raisedHandScrollsUp() {
        var rig = Rig.scrolling()
        let amounts = scrolls(in: rig.hold(y: 0.80, for: 0.5))
        #expect(!amounts.isEmpty)
        #expect(amounts.allSatisfy { $0 > 0 })
    }

    @Test("lowering two fingers past the dead zone scrolls down")
    func loweredHandScrollsDown() {
        var rig = Rig.scrolling()
        let amounts = scrolls(in: rig.hold(y: 0.20, for: 0.5))
        #expect(!amounts.isEmpty)
        #expect(amounts.allSatisfy { $0 < 0 })
    }

    @Test("a hand resting inside the dead zone does not scroll, but raising it does")
    func deadZone() {
        var rig = Rig.scrolling()
        let resting = scrolls(in: rig.hold(y: 0.55, for: 1.0))
        #expect(resting.isEmpty)
        let raised = scrolls(in: rig.hold(y: 0.75, for: 0.5))
        #expect(!raised.isEmpty)
    }

    @Test("scroll speed grows with distance from neutral and caps at full speed")
    func speedGrowsAndCaps() {
        // Amount per frame is rate * dt. With the default config the dead zone
        // is 0.06 and full speed is reached at an offset of 0.30.
        func steadyAmount(offset: Double) -> Double {
            var config = GestureConfig()
            config.scrollMode = .rate
            var rig = Rig.scrolling(config: config)
            rig.move(toX: 0.5, toY: 0.5 + offset, over: 0.3)
            return scrolls(in: rig.hold(for: 0.3)).last ?? 0
        }
        let dt = 1.0 / 30.0
        #expect(abs(steadyAmount(offset: 0.12) - 0.25 * dt) < 1e-9)
        #expect(abs(steadyAmount(offset: 0.24) - 0.75 * dt) < 1e-9)
        #expect(abs(steadyAmount(offset: 0.40) - 1.00 * dt) < 1e-9)
    }

    @Test("an open palm never scrolls, but two fingers lowered from there do")
    func openPalmDoesNotScroll() {
        var rig = Rig.armed()
        let palm = scrolls(in: rig.hold(y: 0.90, for: 0.5))
        #expect(palm.isEmpty)
        rig.show(.twoFingers)
        let lowered = scrolls(in: rig.move(toX: 0.5, toY: 0.5, over: 0.3))
        #expect(!lowered.isEmpty)
        #expect(lowered.allSatisfy { $0 < 0 })
    }

    @Test("one finger does not scroll by height: moved up quickly or held high, nothing moves")
    func oneFingerDoesNotScroll() {
        var rig = Rig.swiping()
        // One finger only swipes sideways. Scrolling is the pinch or two fingers.
        let rise = scrolls(in: rig.move(toX: 0.5, toY: 0.90, over: 0.4))
        let held = scrolls(in: rig.hold(for: 0.5))
        #expect(rise.isEmpty)
        #expect(held.isEmpty)
        rig.show(.twoFingers)
        let lowered = scrolls(in: rig.move(toX: 0.5, toY: 0.5, over: 0.3))
        #expect(!lowered.isEmpty)
    }

    @Test("scroll is measured from where the two-finger pose appeared, not from where the palm armed")
    func neutralIsWhereTwoFingersAppear() {
        var rig = Rig.armed()
        rig.hold(y: 0.80, for: 0.3)
        rig.show(.twoFingers)
        let resting = scrolls(in: rig.hold(for: 0.5))
        #expect(resting.isEmpty)
        let raised = scrolls(in: rig.move(toX: 0.5, toY: 0.95, over: 0.3))
        #expect(!raised.isEmpty)
        #expect(raised.allSatisfy { $0 > 0 })
    }

    @Test("scrolling stops once the pose is no longer two fingers")
    func scrollStopsWhenPoseChanges() {
        var rig = Rig.scrolling()
        let whileScrolling = scrolls(in: rig.hold(y: 0.80, for: 0.4))
        #expect(!whileScrolling.isEmpty)
        rig.show(.openPalm)
        let after = scrolls(in: rig.hold(for: 0.5))
        #expect(after.isEmpty)
    }

    // Field evidence: with "hand height sets speed", lowering a raised hand kept
    // scrolling UP until it crossed the start height, which read as "up and down
    // does not work". The page should follow the hand's movement instead.
    @Test("the page follows the hand: moving up scrolls up, moving down scrolls down")
    func pageFollowsTheHand() {
        var rig = Rig.scrolling()
        let up = scrolls(in: rig.move(toX: 0.5, toY: 0.75, over: 0.4))
        #expect(!up.isEmpty)
        #expect(up.allSatisfy { $0 > 0 })
        rig.hold(for: 0.5)
        // Still higher than where it started, but moving down: this must scroll down.
        let down = scrolls(in: rig.move(toX: 0.5, toY: 0.60, over: 0.4))
        #expect(!down.isEmpty)
        #expect(down.allSatisfy { $0 < 0 })
    }

    @Test("a hand held still stops scrolling, even when it is held high")
    func heldHighHandStopsScrolling() {
        var rig = Rig.scrolling()
        rig.move(toX: 0.5, toY: 0.80, over: 0.4)
        rig.hold(for: 0.5)
        let held = scrolls(in: rig.hold(for: 1.0))
        #expect(held.isEmpty)
    }

    @Test("scroll distance is proportional to how far the hand moves")
    func scrollIsProportionalToMovement() {
        func total(forRise rise: Double) -> Double {
            var rig = Rig.scrolling()
            var amounts = scrolls(in: rig.move(toX: 0.5, toY: 0.5 + rise, over: 0.4))
            amounts += scrolls(in: rig.hold(for: 1.0))
            return amounts.reduce(0, +)
        }
        let small = total(forRise: 0.1)
        let large = total(forRise: 0.2)
        #expect(small > 0)
        #expect(abs(large / small - 2.0) < 0.15)
    }

    @Test("the original hand-height model is still available, and keeps scrolling while held")
    func rateModeKeepsScrollingWhileHeld() {
        var config = GestureConfig()
        config.scrollMode = .rate
        var rig = Rig.scrolling(config: config)
        rig.move(toX: 0.5, toY: 0.80, over: 0.4)
        let held = scrolls(in: rig.hold(for: 1.0))
        #expect(!held.isEmpty)
    }
}

// MARK: - Disarm

@Suite("Disarm")
struct DisarmTests {
    @Test("a fist held past the threshold stops it")
    func fistDisarms() {
        var rig = Rig.armed()
        let events = rig.hold(for: 0.8, pose: .fist)
        #expect(events == [.disarmed])
    }

    @Test("a brief fist flicker does not disarm")
    func briefFistIgnored() {
        var rig = Rig.swiping()
        let flicker = rig.hold(for: 0.1, pose: .fist)
        #expect(flicker.isEmpty)
        let swipe = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: swipe) == [.swipe(.right)])
    }

    // Field evidence: swipe dips lasted up to ~0.25 s; a real fist is held longer.
    @Test("a 0.3 s fist dip does not disarm, but a held fist does")
    func fistNeedsToPersist() {
        var rig = Rig.armed()
        let dip = rig.hold(for: 0.3, pose: .fist)
        #expect(dip.isEmpty)
        let open = rig.hold(for: 0.2)
        #expect(open.isEmpty)
        let fist = rig.hold(for: 0.8, pose: .fist)
        #expect(fist == [.disarmed])
    }

    // Field evidence: low in the frame a moving hand often reads as a fist for a moment, and
    // "sometimes it disarms because it looks closed". A real stop is a fist held
    // still, just as a palm held still is what starts it.
    @Test("a fist-like reading while the hand is moving does not stop it")
    func movingFistDoesNotDisarm() {
        var rig = Rig.swiping()
        let events = rig.move(toX: 0.85, toY: 0.5, over: 1.2, pose: .fist)
        #expect(!events.contains(.disarmed))
    }

    @Test("a fist that moves and then holds still does stop it")
    func fistThatSettlesDisarms() {
        var rig = Rig.swiping()
        rig.move(toX: 0.85, toY: 0.5, over: 0.5, pose: .fist)
        let events = rig.hold(for: 0.8, pose: .fist)
        #expect(events.contains(.disarmed))
    }

    @Test("a pose that is neither a fist nor a mode never disarms")
    func inBetweenPoseNeverDisarms() {
        var rig = Rig.armed()
        let events = rig.hold(for: 3.0, pose: .other)
        #expect(events.isEmpty)
    }

    @Test("two fingers held for a long time is not a fist")
    func twoFingersIsNotAFist() {
        var rig = Rig.scrolling()
        let events = rig.hold(for: 3.0)
        #expect(events.isEmpty)
    }

    @Test("losing the hand for a second stops it")
    func handLostDisarms() {
        var rig = Rig.armed()
        let events = rig.noHand(for: 1.2)
        #expect(events == [.disarmed])
    }

    @Test("a short dropout does not disarm")
    func shortDropoutIgnored() {
        var rig = Rig.swiping()
        let dropout = rig.noHand(for: 0.5)
        #expect(dropout.isEmpty)
        let swipe = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: swipe) == [.swipe(.right)])
    }

    @Test("holding still with no gesture past the idle timeout stops it")
    func idleDisarms() {
        var rig = Rig.armed()
        let events = rig.hold(for: 17.0)
        #expect(events == [.disarmed])
    }

    // Field evidence: the old 6 s timeout fired while a palm was held up and open.
    @Test("an armed hand can rest for ten seconds without being disarmed")
    func restingHandStaysArmed() {
        var rig = Rig.armed()
        let events = rig.hold(for: 10.0)
        #expect(events.isEmpty)
    }

    @Test("gesture activity resets the idle timer")
    func activityResetsIdle() {
        var rig = Rig.swiping()
        rig.hold(for: 10.0)
        let swipe = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: swipe) == [.swipe(.right)])
        let later = rig.hold(for: 10.0)
        #expect(later.isEmpty)
    }

    @Test("after an idle timeout the hand must leave before it can arm again")
    func idleDisarmRequiresRelease() {
        var rig = Rig.armed()
        let idle = rig.hold(for: 17.0)
        #expect(idle == [.disarmed])
        rig.noHand(for: 0.3)
        let rearmed = rig.hold(for: 0.8)
        #expect(rearmed == [.armed])
    }

    @Test("after a fist, fast moves do nothing until the palm is held still again")
    func disarmedIgnoresSwipes() {
        var rig = Rig.swiping()
        rig.hold(for: 0.8, pose: .fist)
        let moving = rig.move(toX: 0.90, toY: 0.5, over: 0.2)
        #expect(moving.isEmpty)
        rig.pose = .openPalm
        let again = rig.hold(for: 0.8)
        #expect(again == [.armed])
    }

    @Test("after re-arming, a fresh two-finger pose measures from its own start height")
    func rearmingStartsAFreshScrollNeutral() {
        var rig = Rig.scrolling()
        rig.hold(for: 0.8, pose: .fist)
        rig.pose = .openPalm
        rig.move(toX: 0.5, toY: 0.8, over: 0.2)
        let rearmed = rig.hold(for: 0.8)
        #expect(rearmed == [.armed])
        rig.show(.twoFingers)
        let resting = rig.hold(for: 0.5)
        #expect(scrolls(in: resting).isEmpty)
    }

    @Test("it reports why it stopped: a held fist")
    func disarmReasonIsFist() {
        var rig = Rig.armed()
        rig.hold(for: 0.8, pose: .fist)
        #expect(rig.engine.lastDisarmReason == .fist)
    }

    @Test("it reports why it stopped: the hand left the view")
    func disarmReasonIsHandLost() {
        var rig = Rig.armed()
        rig.noHand(for: 1.2)
        #expect(rig.engine.lastDisarmReason == .handLost)
    }

    @Test("it reports why it stopped: nothing happened for too long")
    func disarmReasonIsIdle() {
        var rig = Rig.armed()
        rig.hold(for: 17.0)
        #expect(rig.engine.lastDisarmReason == .idle)
    }
}

// MARK: - Pinch scroll

/// Thumb and index fingertip touching is a finger on the glass: the page follows the hand
/// up and down, and opening the pinch lifts the finger, so the way back scrolls nothing.
/// Field evidence (live captures, 2026-10-16): flicks from the finger's shape kept mixing
/// up and down because there is no "finger up" in the air, and one finger was read as one
/// finger in only 52 to 66% of frames while the hand moved. The pinch distance stayed
/// 0.01 to 0.17 through whole drags, whatever the other fingers looked like.
@Suite("Pinch scroll")
struct PinchScrollTests {
    private let gain = GestureConfig().pinchScrollGain
    private let pinched = 0.08
    private let apart = 1.5

    private func total(_ events: [GestureEvent]) -> Double {
        scrolls(in: events).reduce(0, +)
    }

    /// Armed, with the fingertips touching for long enough to have grabbed the page.
    private func grabbed(config: GestureConfig = GestureConfig()) -> Rig {
        var rig = Rig.armed(config: config)
        rig.pinch = pinched
        rig.hold(for: 0.3)
        return rig
    }

    @Test("dragging a pinched hand up scrolls up by about the distance moved")
    func dragUp() {
        var rig = grabbed()
        var events = rig.move(toX: 0.5, toY: 0.70, over: 0.6)
        events += rig.hold(for: 0.3)
        #expect(abs(total(events) - 0.20 * gain) < 0.06)
        #expect(scrolls(in: events).allSatisfy { $0 >= 0 })
    }

    @Test("dragging a pinched hand down scrolls down")
    func dragDown() {
        var rig = grabbed()
        var events = rig.move(toX: 0.5, toY: 0.30, over: 0.6)
        events += rig.hold(for: 0.3)
        #expect(abs(total(events) + 0.20 * gain) < 0.06)
        #expect(scrolls(in: events).allSatisfy { $0 <= 0 })
    }

    @Test("a farther drag scrolls proportionally farther")
    func proportional() {
        var small = grabbed()
        var smallEvents = small.move(toX: 0.5, toY: 0.60, over: 0.6)
        smallEvents += small.hold(for: 0.3)
        var big = grabbed()
        var bigEvents = big.move(toX: 0.5, toY: 0.80, over: 0.6)
        bigEvents += big.hold(for: 0.3)
        #expect(abs(total(bigEvents) / total(smallEvents) - 3.0) < 0.4)
    }

    @Test("an open hand moving up and down scrolls nothing")
    func openHandDoesNotScroll() {
        var rig = Rig.armed()
        rig.pinch = apart
        rig.hold(for: 0.3)
        let up = rig.move(toX: 0.5, toY: 0.70, over: 0.5)
        let down = rig.move(toX: 0.5, toY: 0.30, over: 0.5)
        #expect(scrolls(in: up).isEmpty)
        #expect(scrolls(in: down).isEmpty)
    }

    @Test("opening the pinch lifts the finger, so the move back scrolls nothing")
    func releaseLiftsTheFinger() {
        var rig = grabbed()
        rig.move(toX: 0.5, toY: 0.70, over: 0.6)
        rig.pinch = apart
        rig.hold(for: 0.3)
        let back = rig.move(toX: 0.5, toY: 0.50, over: 0.6)
        #expect(scrolls(in: back).isEmpty)
    }

    @Test("pinching again anywhere carries on, like lifting a finger to scroll farther")
    func grabAgain() {
        var rig = grabbed()
        var events = rig.move(toX: 0.5, toY: 0.70, over: 0.6)
        events += rig.hold(for: 0.3)
        rig.pinch = apart
        rig.hold(for: 0.3)
        let back = rig.move(toX: 0.5, toY: 0.50, over: 0.6)
        rig.hold(for: 0.2)
        rig.pinch = pinched
        rig.hold(for: 0.3)
        var second = rig.move(toX: 0.5, toY: 0.70, over: 0.6)
        second += rig.hold(for: 0.3)
        #expect(scrolls(in: back).isEmpty)
        #expect(abs(total(events) + total(second) - 0.40 * gain) < 0.12)
    }

    @Test("grabbing the page does not make it jump, wherever the hand is")
    func noJumpOnGrab() {
        var rig = Rig.armed()
        rig.pinch = apart
        rig.move(toX: 0.5, toY: 0.80, over: 0.5)
        rig.hold(for: 0.3)
        rig.pinch = pinched
        let events = rig.hold(for: 0.6)
        #expect(scrolls(in: events).isEmpty)
    }

    @Test("a reading between touching and apart changes nothing, so a wobble does not stutter")
    func hysteresis() {
        var open = Rig.armed()
        open.pinch = 0.25
        open.hold(for: 0.3)
        let notGrabbed = open.move(toX: 0.5, toY: 0.70, over: 0.6)
        #expect(scrolls(in: notGrabbed).isEmpty)

        var held = grabbed()
        held.pinch = 0.25
        let kept = held.move(toX: 0.5, toY: 0.70, over: 0.6)
        #expect(total(kept) > 0.5 * 0.20 * gain)
    }

    @Test("fingertips that only brush past do not grab the page")
    func briefTouchDoesNotGrab() {
        var rig = Rig.armed()
        rig.pinch = pinched
        rig.move(toX: rig.x, toY: rig.y, over: 1 / rig.fps)
        rig.pinch = 0.25
        let events = rig.move(toX: 0.5, toY: 0.70, over: 0.6)
        #expect(scrolls(in: events).isEmpty)
    }

    @Test("a pinch the camera cannot read for a moment keeps its grip")
    func unreadableMomentKeepsTheGrip() {
        var rig = grabbed()
        rig.pinch = nil
        rig.hold(for: 0.1)
        rig.pinch = pinched
        var events = rig.move(toX: 0.5, toY: 0.70, over: 0.4)
        events += rig.hold(for: 0.3)
        #expect(abs(total(events) - 0.20 * gain) < 0.08)
    }

    @Test("it scrolls whatever the other fingers look like")
    func anyPoseScrolls() {
        for pose in [HandPose.other, .fist, .thumbsUp, .oneFinger, .openPalm] {
            var rig = grabbed()
            rig.pose = pose
            var events = rig.move(toX: 0.5, toY: 0.70, over: 0.6)
            events += rig.hold(for: 0.3)
            #expect(total(events) > 0.5 * 0.20 * gain, "pose \(pose)")
        }
    }

    @Test("a pinch with curled fingers reading as a fist does not stop the engine")
    func pinchBeatsFist() {
        var rig = grabbed()
        rig.pose = .fist
        let events = rig.hold(for: 1.0)
        #expect(!events.contains(.disarmed))
    }

    @Test("nor does a pinch with curled fingers reading as a thumbs up send")
    func pinchBeatsThumbsUp() {
        var config = GestureConfig()
        config.sendEnabled = true
        var rig = grabbed(config: config)
        rig.pose = .thumbsUp
        let events = rig.hold(for: 1.5)
        #expect(!events.contains(.send))
    }

    @Test("pinched sideways moves do not swipe")
    func pinchedSidewaysDoesNotSwipe() {
        var rig = Rig.swiping()
        rig.pinch = pinched
        rig.hold(for: 0.3)
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: events).isEmpty)
    }

    @Test("a swipe still works once the pinch is let go")
    func swipeAfterRelease() {
        var rig = Rig.swiping()
        rig.pinch = pinched
        rig.hold(for: 0.3)
        rig.pinch = apart
        rig.hold(for: 0.6)
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: events) == [.swipe(.right)])
    }

    @Test("nothing scrolls before the engine is armed")
    func needsArming() {
        var rig = Rig()
        rig.pinch = pinched
        rig.pose = .other
        rig.hold(for: 0.3)
        let events = rig.move(toX: 0.5, toY: 0.80, over: 0.6)
        #expect(scrolls(in: events).isEmpty)
    }

    @Test("pinch scrolling can be turned off")
    func canBeDisabled() {
        var config = GestureConfig()
        config.pinchEnabled = false
        var rig = grabbed(config: config)
        let events = rig.move(toX: 0.5, toY: 0.70, over: 0.6)
        #expect(scrolls(in: events).isEmpty)
    }
}

// MARK: - Diagnostics

/// `lastRejection` is a debugging aid: when a move is big enough to be a swipe
/// but is turned down, it says why, so a run on a real camera can show whether a
/// missing swipe was held by the guard, the cooldown, the pose, or the angle.
@Suite("Diagnostics")
struct DiagnosticsTests {
    @Test("a hand at rest has nothing rejected")
    func restingHandRejectsNothing() {
        var rig = Rig.swiping()
        rig.hold(for: 0.5)
        #expect(rig.engine.lastRejection == nil)
    }

    @Test("a swipe made in the wrong pose says which mode it was in")
    func wrongModeIsExplained() {
        var rig = Rig.armed()
        // A turned-down move is forgotten, so the reason shows on the frame it was turned
        // down, not on every frame after. Move one frame at a time and keep the reasons.
        var reasons: [String] = []
        for step in 1...8 {
            rig.move(toX: 0.5 + 0.0375 * Double(step), toY: 0.5, over: 1 / rig.fps)
            if let why = rig.engine.lastRejection { reasons.append(why) }
        }
        let why = reasons.first ?? ""
        #expect(why.contains("right"))
        #expect(why.contains("mode is openPalm"))
    }

    @Test("a second swipe the same way before the return is reported as held")
    func sameWayWhileGuardedIsExplained() {
        var rig = Rig.swiping()
        rig.move(toX: 0.75, toY: 0.5, over: 0.25)
        rig.move(toX: 0.95, toY: 0.5, over: 0.20)
        let why = rig.engine.lastRejection ?? ""
        #expect(why.contains("right"))
        #expect(why.contains("same way"))
    }

    @Test("a sideways return that stops short of a full stroke past home reports the shortfall")
    func shortSidewaysCarryOnIsExplained() {
        var rig = Rig.swiping()
        rig.move(toX: 0.75, toY: 0.5, over: 0.25)
        // Back left past home (0.5) by 0.05: short of the 0.12 a carry-on needs.
        rig.move(toX: 0.45, toY: 0.5, over: 0.20)
        let why = rig.engine.lastRejection ?? ""
        #expect(why.contains("left"))
        #expect(why.contains("past home"))
    }

    @Test("a diagonal move says it was too far off the axis")
    func diagonalIsExplained() {
        var rig = Rig.swiping()
        rig.move(toX: 0.68, toY: 0.68, over: 0.25)
        #expect((rig.engine.lastRejection ?? "").contains("off the axis"))
    }
}

// MARK: - Unclear poses

/// Field evidence: with the hand low in the frame, or moving fast, the pose reads as
/// `other` or `fist` for long stretches (46 of 64 readings in one real run), and the
/// engine was dropping out of one-finger mode, so moves two to three times the
/// threshold were ignored. A reading that is merely unclear must not end the mode.
@Suite("Unclear poses")
struct UnclearPoseTests {
    @Test("a swipe counts through a brief fist reading and a pose that flickers")
    func swipeThroughFlickeringPose() {
        var rig = Rig.swiping()
        rig.hold(for: 0.3, pose: .fist)
        var events: [GestureEvent] = []
        events += rig.move(toX: 0.62, toY: 0.5, over: 0.1, pose: .other)
        events += rig.move(toX: 0.74, toY: 0.5, over: 0.1, pose: .fist)
        events += rig.move(toX: 0.86, toY: 0.5, over: 0.1, pose: .other)
        #expect(swipes(in: events) == [.swipe(.right)])
    }

    @Test("a swipe counts with an unclear pose too")
    func swipeWithUnclearPose() {
        var rig = Rig.swiping()
        rig.hold(for: 0.4, pose: .other)
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.2, pose: .other)
        #expect(swipes(in: events) == [.swipe(.right)])
    }

    @Test("a one-finger reading now and then keeps the mode alive")
    func occasionalOneFingerKeepsTheMode() {
        var rig = Rig.swiping()
        for _ in 0..<4 {
            rig.hold(for: 0.5, pose: .other)
            rig.hold(for: 0.1, pose: .oneFinger)
        }
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.2, pose: .other)
        #expect(swipes(in: events) == [.swipe(.right)])
    }

    @Test("but a long stretch of nothing like one finger ends the mode")
    func longUnclearStretchEndsTheMode() {
        var rig = Rig.swiping()
        rig.hold(for: 1.5, pose: .other)
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.2, pose: .other)
        #expect(swipes(in: events).isEmpty)
        // One finger, shown steadily again, works as usual. Settle first, so the
        // move above is no longer in the window when the mode comes back.
        rig.hold(for: 0.6, pose: .other)
        rig.show(.oneFinger)
        let again = rig.move(toX: 0.50, toY: 0.5, over: 0.2)
        #expect(swipes(in: again) == [.swipe(.left)])
    }

    @Test("a steady open palm still takes over from one finger")
    func openPalmTakesOver() {
        var rig = Rig.swiping()
        rig.show(.openPalm)
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: events).isEmpty)
    }

    @Test("two fingers still take over from one finger")
    func twoFingersTakeOver() {
        var rig = Rig.swiping()
        rig.show(.twoFingers)
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: events).isEmpty)
    }

    @Test("open-palm glimpses between unclear readings never add up to a switch")
    func palmGlimpsesDoNotAddUp() {
        var rig = Rig.swiping()
        for _ in 0..<4 {
            rig.hold(for: 0.1, pose: .openPalm)
            rig.hold(for: 0.1, pose: .other)
        }
        // A swipe is not made within `swipePalmGuard` (0.4 s) of an open palm, so let that
        // pass. One-finger readings keep the mode alive meanwhile: the mode is still
        // one finger, which is the point of this test.
        rig.hold(for: 0.1, pose: .oneFinger)
        rig.hold(for: 0.45, pose: .other)
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.2, pose: .other)
        #expect(swipes(in: events) == [.swipe(.right)])
    }
}

// MARK: - Circle

extension Rig {
    /// Draws a circle that is round in the picture, starting at the current position
    /// (the circle's rightmost point). Counter-clockwise unless `clockwise`.
    @discardableResult
    mutating func drawCircle(radius: Double, seconds: Double, turns: Double = 1.0,
                             clockwise: Bool = false, pose override: HandPose? = nil) -> [GestureEvent] {
        let steps = max(1, Int((seconds * fps).rounded()))
        let centerX = x - radius
        let centerY = y
        let sign = clockwise ? -1.0 : 1.0
        var events: [GestureEvent] = []
        for step in 1...steps {
            let angle = sign * turns * 2 * .pi * Double(step) / Double(steps)
            events += move(toX: centerX + radius * cos(angle),
                           toY: centerY + radius * sin(angle) / 0.75,
                           over: seconds / Double(steps), pose: override)
        }
        return events
    }
}

@Suite("Circle")
struct CircleEngineTests {
    private func voiceConfig() -> GestureConfig {
        var config = GestureConfig()
        config.circleEnabled = true
        return config
    }

    @Test("an open-palm circle is a circle, and nothing else")
    func palmCircle() {
        var rig = Rig.armed(config: voiceConfig())
        let events = rig.drawCircle(radius: 0.10, seconds: 1.0)
        #expect(events == [.circle])
    }

    @Test("a clockwise palm circle counts too")
    func palmCircleClockwise() {
        var rig = Rig.armed(config: voiceConfig())
        let events = rig.drawCircle(radius: 0.10, seconds: 1.0, clockwise: true)
        #expect(events == [.circle])
    }

    @Test("a second circle straight away is ignored, one after the cooldown counts")
    func cooldown() {
        var rig = Rig.armed(config: voiceConfig())
        var events = rig.drawCircle(radius: 0.10, seconds: 1.0)
        events += rig.drawCircle(radius: 0.10, seconds: 0.3, turns: 0.3)
        rig.hold(for: 2.0)
        events += rig.drawCircle(radius: 0.10, seconds: 1.0)
        #expect(events == [.circle, .circle])
    }

    @Test("with voice off, a palm circle does nothing")
    func offByDefault() {
        var rig = Rig.armed()
        #expect(rig.drawCircle(radius: 0.10, seconds: 1.0).isEmpty)
    }

    @Test("a circle while not armed does nothing")
    func notArmed() {
        var rig = Rig(config: voiceConfig())
        #expect(rig.drawCircle(radius: 0.10, seconds: 1.0).isEmpty)
    }

    @Test("a half circle does nothing")
    func halfCircle() {
        var rig = Rig.armed(config: voiceConfig())
        #expect(rig.drawCircle(radius: 0.10, seconds: 0.5, turns: 0.5).isEmpty)
    }

    @Test("one finger drawing a circle is not a voice circle")
    func oneFingerCircle() {
        var rig = Rig.swiping(config: voiceConfig())
        let events = rig.drawCircle(radius: 0.10, seconds: 1.0)
        #expect(!events.contains(.circle))
    }

    @Test("two fingers drawing a circle is not a voice circle")
    func twoFingerCircle() {
        var rig = Rig.scrolling(config: voiceConfig())
        let events = rig.drawCircle(radius: 0.10, seconds: 1.0)
        #expect(!events.contains(.circle))
    }

    // The whole stretch (hold plus circle up to the moment it completes) must stay inside
    // `strokePoseHold` (1 s), or palm mode lapses mid-circle on purpose.
    @Test("palm mode survives unclear pose readings, so the circle still counts")
    func unclearPoseKeepsPalmMode() {
        var rig = Rig.armed(config: voiceConfig())
        rig.hold(for: 0.2, pose: .other)
        let events = rig.drawCircle(radius: 0.10, seconds: 0.7, pose: .other)
        #expect(events == [.circle])
    }

    @Test("but a long stretch with no palm reading ends palm mode")
    func longUnclearStretchEndsPalmMode() {
        var rig = Rig.armed(config: voiceConfig())
        rig.hold(for: 1.5, pose: .other)
        let events = rig.drawCircle(radius: 0.10, seconds: 1.0, pose: .other)
        #expect(events.isEmpty)
    }

    @Test("a held fist still stops it, even in palm mode")
    func fistStillDisarms() {
        var rig = Rig.armed(config: voiceConfig())
        let events = rig.hold(for: 0.8, pose: .fist)
        #expect(events.contains(.disarmed))
    }

    // Field evidence (final live test, 2026-10-16): a palm circle also switched screens.
    // Real loops are big (about 0.35 wide), so their first quarter looks like a swipe. In
    // palm mode that is ignored, but when the camera read the hand as one finger for just
    // 0.15 s mid-circle the mode flipped to one finger and the swipe fired. A pose shown
    // while the hand is moving must not become the mode.
    @Test("a pose shown while the hand is moving does not become the mode")
    func movingPoseDoesNotSwitchMode() {
        var rig = Rig.armed(config: voiceConfig())
        rig.pose = .oneFinger
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.6)
        #expect(swipes(in: events).isEmpty)
    }

    @Test("a real palm circle that the camera reads as one finger does not switch screens")
    func recordedCircleReadAsOneFinger() {
        // Recorded start circle, 10 samples a second (see CircleDetectorTests).
        let loop: [(t: Double, x: Double, y: Double)] = [
            (14.0, 0.65, 0.27), (14.2, 0.59, 0.21), (14.3, 0.45, 0.26), (14.4, 0.41, 0.25),
            (14.5, 0.37, 0.29), (14.6, 0.36, 0.42), (14.8, 0.40, 0.53), (14.9, 0.45, 0.60),
            (15.0, 0.54, 0.62), (15.1, 0.61, 0.59), (15.3, 0.68, 0.50), (15.4, 0.72, 0.40),
            (15.5, 0.70, 0.30), (15.6, 0.65, 0.26), (15.7, 0.59, 0.23), (15.9, 0.54, 0.28),
            (16.0, 0.53, 0.32),
        ]
        var rig = Rig.armed(config: voiceConfig())
        let start = rig.time + 0.1
        var events: [GestureEvent] = []
        for (index, point) in loop.enumerated() {
            // A palm to begin with, then the reading drops to one finger and stays there.
            let pose: HandPose = index < 2 ? .openPalm : .oneFinger
            events += rig.engine.process(HandSample(x: point.x, y: point.y, pose: pose),
                                         at: start + (point.t - loop[0].t))
        }
        #expect(swipes(in: events).isEmpty)
    }

    // Second live test (circle2.log, 2026-10-16): after a swipe the engine is in one-finger
    // mode, and the user went straight into a palm circle without pausing. The hand showed an
    // open palm for a full second, but the mode stayed one finger (a new pose had to be held
    // still) and the circle's sideways travel fired a swipe. An open palm is the one pose the
    // camera does not misread, so it must win at once.
    @Test("a palm circle drawn straight after a swipe is a circle, not another swipe")
    func circleStraightAfterASwipe() {
        var rig = Rig.swiping(config: voiceConfig())
        let swipe = rig.move(toX: 0.75, toY: 0.5, over: 0.25)
        #expect(swipes(in: swipe) == [.swipe(.right)])
        rig.pose = .openPalm
        let events = rig.drawCircle(radius: 0.12, seconds: 1.0)
        #expect(swipes(in: events).isEmpty)
        #expect(events.contains(.circle))
    }

    @Test("a sideways move right after an open palm was showing is not a swipe")
    func noSwipeRightAfterAPalm() {
        var rig = Rig.swiping(config: voiceConfig())
        // A brief palm reading, too short to change the mode, then a move with one finger.
        rig.hold(for: 0.1, pose: .openPalm)
        let early = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: early).isEmpty)
        // A moment later the same move is an ordinary swipe.
        rig.hold(for: 0.6)
        let later = rig.move(toX: 0.50, toY: 0.5, over: 0.2)
        #expect(swipes(in: later) == [.swipe(.left)])
    }

    @Test("showing one finger and holding it still still switches to swiping")
    func stillPoseStillSwitchesMode() {
        var rig = Rig.armed(config: voiceConfig())
        rig.show(.oneFinger)
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: events) == [.swipe(.right)])
    }
}

// MARK: - Send (thumbs up)

@Suite("Send")
struct SendTests {
    private func sendConfig() -> GestureConfig {
        var config = GestureConfig()
        config.sendEnabled = true
        return config
    }

    @Test("a thumbs up held still sends once")
    func thumbsUpSends() {
        var rig = Rig.armed(config: sendConfig())
        let events = rig.hold(for: 1.2, pose: .thumbsUp)
        #expect(events == [.send])
    }

    @Test("holding it longer still sends only once")
    func sendsOncePerHold() {
        var rig = Rig.armed(config: sendConfig())
        let events = rig.hold(for: 4.0, pose: .thumbsUp)
        #expect(events == [.send])
    }

    @Test("a thumbs up shown for less than the hold does not send")
    func tooShort() {
        var rig = Rig.armed(config: sendConfig())
        #expect(rig.hold(for: 0.5, pose: .thumbsUp).isEmpty)
    }

    @Test("a moving thumbs up does not send")
    func movingThumbsUp() {
        var rig = Rig.armed(config: sendConfig())
        let events = rig.move(toX: 0.9, toY: 0.5, over: 1.5, pose: .thumbsUp)
        #expect(events.isEmpty)
    }

    @Test("lowering the thumb and raising it again sends again")
    func sendsAgainAfterRelease() {
        var rig = Rig.armed(config: sendConfig())
        var events = rig.hold(for: 1.0, pose: .thumbsUp)
        events += rig.hold(for: 0.4)
        events += rig.hold(for: 1.0, pose: .thumbsUp)
        #expect(events == [.send, .send])
    }

    @Test("a brief flicker to an unclear pose in the middle of the hold is forgiven")
    func flickerIsForgiven() {
        var rig = Rig.armed(config: sendConfig())
        var events = rig.hold(for: 0.3, pose: .thumbsUp)
        events += rig.hold(for: 0.1, pose: .other)
        events += rig.hold(for: 0.1, pose: .fist)
        events += rig.hold(for: 0.5, pose: .thumbsUp)
        #expect(events == [.send])
    }

    @Test("but a longer gap, or a clear different pose, ends the hold")
    func longerGapEndsTheHold() {
        var rig = Rig.armed(config: sendConfig())
        var events = rig.hold(for: 0.4, pose: .thumbsUp)
        events += rig.hold(for: 0.5, pose: .other)
        events += rig.hold(for: 0.4, pose: .thumbsUp)
        #expect(events.isEmpty)

        var other = Rig.armed(config: sendConfig())
        var more = other.hold(for: 0.4, pose: .thumbsUp)
        more += other.hold(for: 0.1)
        more += other.hold(for: 0.4, pose: .thumbsUp)
        #expect(more.isEmpty)
    }

    @Test("a thumbs up never stops it, however long it is held")
    func thumbsUpDoesNotDisarm() {
        var rig = Rig.armed(config: sendConfig())
        let events = rig.hold(for: 3.0, pose: .thumbsUp)
        #expect(!events.contains(.disarmed))
    }

    @Test("a held fist still stops it, with send turned on")
    func fistStillDisarms() {
        var rig = Rig.armed(config: sendConfig())
        let events = rig.hold(for: 0.8, pose: .fist)
        #expect(events.contains(.disarmed))
        #expect(!events.contains(.send))
    }

    @Test("send is off unless it is turned on")
    func offByDefault() {
        var rig = Rig.armed()
        #expect(rig.hold(for: 1.5, pose: .thumbsUp).isEmpty)
    }

    @Test("a thumbs up while not armed does nothing")
    func notArmed() {
        var rig = Rig(config: sendConfig())
        #expect(rig.hold(for: 1.5, pose: .thumbsUp).isEmpty)
    }
}
