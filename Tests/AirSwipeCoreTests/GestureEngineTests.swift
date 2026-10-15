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
            events += engine.process(HandSample(x: x, y: y, pose: shown), at: time)
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

    // A mostly vertical move used to be ignored; it is now a flick (see FlickTests).
    // What still holds is that it is never a swipe, and that swiping works again once
    // the hand has come back to where the flick started.
    @Test("a mostly vertical move is a flick, not a swipe, and swiping works after the return")
    func verticalMoveIsNotASwipe() {
        var rig = Rig.swiping()
        let flick = rig.move(toX: 0.70, toY: 0.90, over: 0.2)
        #expect(swipes(in: flick).isEmpty)
        rig.hold(for: 0.5)
        rig.move(toX: 0.50, toY: 0.50, over: 0.25)
        rig.hold(for: 0.5)
        let real = rig.move(toX: 0.20, toY: 0.50, over: 0.2)
        #expect(swipes(in: real) == [.swipe(.left)])
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

    @Test("one finger never scrolls, however high it is")
    func oneFingerDoesNotScroll() {
        var rig = Rig.swiping()
        let amounts = scrolls(in: rig.hold(y: 0.90, for: 0.5))
        #expect(amounts.isEmpty)
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

// MARK: - Flick (vertical move in one-finger mode: scroll about a screen)

/// Only the flick events.
private func flicks(in events: [GestureEvent]) -> [GestureEvent] {
    events.filter {
        if case .flick = $0 { return true }
        return false
    }
}

@Suite("Flick")
struct FlickTests {
    @Test("a fast move up with one finger is a flick up")
    func flickUp() {
        var rig = Rig.swiping()
        let events = rig.move(toX: 0.5, toY: 0.72, over: 0.25)
        #expect(flicks(in: events) == [.flick(.up)])
        #expect(swipes(in: events).isEmpty)
    }

    @Test("a fast move down with one finger is a flick down")
    func flickDown() {
        var rig = Rig.swiping()
        let events = rig.move(toX: 0.5, toY: 0.28, over: 0.25)
        #expect(flicks(in: events) == [.flick(.down)])
    }

    @Test("a sideways swipe is a swipe, not a flick")
    func swipeIsNotAFlick() {
        var rig = Rig.swiping()
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: events) == [.swipe(.right)])
        #expect(flicks(in: events).isEmpty)
    }

    @Test("a diagonal move is neither, but a clean flick afterward still works")
    func diagonalIsNeither() {
        var rig = Rig.swiping()
        let diagonal = rig.move(toX: 0.68, toY: 0.68, over: 0.25)
        #expect(swipes(in: diagonal).isEmpty)
        #expect(flicks(in: diagonal).isEmpty)
        rig.hold(for: 0.5)
        let clean = rig.move(toX: 0.68, toY: 0.90, over: 0.25)
        #expect(flicks(in: clean) == [.flick(.up)])
    }

    @Test("a slow vertical drift is not a flick, but a quick move afterward is")
    func slowVerticalDriftIsNotAFlick() {
        var rig = Rig.swiping()
        let drift = rig.move(toX: 0.5, toY: 0.85, over: 2.0)
        #expect(flicks(in: drift).isEmpty)
        let quick = rig.move(toX: 0.5, toY: 0.55, over: 0.25)
        #expect(flicks(in: quick) == [.flick(.down)])
    }

    @Test("the return stroke after a flick is ignored")
    func returnAfterFlickIsIgnored() {
        var rig = Rig.swiping()
        let up = rig.move(toX: 0.5, toY: 0.72, over: 0.25)
        #expect(flicks(in: up) == [.flick(.up)])
        rig.hold(for: 1.0)
        let back = rig.move(toX: 0.5, toY: 0.5, over: 0.25)
        #expect(flicks(in: back).isEmpty)
        #expect(swipes(in: back).isEmpty)
    }

    @Test("a flick straight after the return, with no pause, is tracked")
    func flickAfterReturnWithoutPause() {
        var rig = Rig.swiping()
        var events: [GestureEvent] = []
        events += rig.move(toX: 0.5, toY: 0.70, over: 0.25)
        events += rig.hold(for: 0.5)
        events += rig.move(toX: 0.5, toY: 0.50, over: 0.25)
        events += rig.move(toX: 0.5, toY: 0.70, over: 0.25)
        #expect(flicks(in: events) == [.flick(.up), .flick(.up)])
    }

    @Test("swipes and flicks can follow each other: right, back to the middle, then up")
    func swipeThenFlick() {
        var rig = Rig.swiping()
        var events: [GestureEvent] = []
        events += rig.move(toX: 0.75, toY: 0.5, over: 0.25)
        events += rig.hold(for: 0.5)
        events += rig.move(toX: 0.50, toY: 0.5, over: 0.25)
        events += rig.hold(for: 0.5)
        events += rig.move(toX: 0.50, toY: 0.72, over: 0.25)
        #expect(swipes(in: events) == [.swipe(.right)])
        #expect(flicks(in: events) == [.flick(.up)])
    }

    @Test("two fingers move the page and do not flick")
    func twoFingersDoNotFlick() {
        var rig = Rig.scrolling()
        let events = rig.move(toX: 0.5, toY: 0.75, over: 0.25)
        #expect(flicks(in: events).isEmpty)
        #expect(!scrolls(in: events).isEmpty)
    }

    @Test("an open palm moving up or down is not a flick, but one finger is")
    func openPalmDoesNotFlick() {
        var rig = Rig.armed()
        let palm = rig.move(toX: 0.5, toY: 0.75, over: 0.25)
        #expect(flicks(in: palm).isEmpty)
        rig.hold(for: 0.5)
        rig.show(.oneFinger)
        let finger = rig.move(toX: 0.5, toY: 0.50, over: 0.25)
        #expect(flicks(in: finger) == [.flick(.down)])
    }

    // Field evidence: a dry run showed seven flicks up and none down. Flicking down
    // straight after flicking up is also the return stroke, which is ignored, so
    // every "down" of an up/down bounce was being swallowed. A move that carries on
    // well past the middle is a deliberate stroke the other way, not a return.
    @Test("flick up, then carry on down past the middle, is a flick down")
    func bounceUpThenDown() {
        var rig = Rig.swiping()
        var events: [GestureEvent] = []
        events += rig.move(toX: 0.5, toY: 0.70, over: 0.25)
        events += rig.move(toX: 0.5, toY: 0.30, over: 0.40)
        #expect(flicks(in: events) == [.flick(.up), .flick(.down)])
    }

    @Test("a continuous up and down bounce flicks every time")
    func continuousBounce() {
        var rig = Rig.swiping()
        var events: [GestureEvent] = []
        events += rig.move(toX: 0.5, toY: 0.70, over: 0.25)
        events += rig.move(toX: 0.5, toY: 0.30, over: 0.40)
        events += rig.move(toX: 0.5, toY: 0.70, over: 0.40)
        events += rig.move(toX: 0.5, toY: 0.30, over: 0.40)
        #expect(flicks(in: events) == [.flick(.up), .flick(.down), .flick(.up), .flick(.down)])
    }

    @Test("a return that only slightly overshoots the middle is still ignored")
    func slightOvershootAfterFlickIsIgnored() {
        var rig = Rig.swiping()
        let up = rig.move(toX: 0.5, toY: 0.70, over: 0.25)
        #expect(flicks(in: up) == [.flick(.up)])
        rig.hold(for: 0.5)
        let back = rig.move(toX: 0.5, toY: 0.44, over: 0.25)
        #expect(flicks(in: back).isEmpty)
    }

    @Test("carrying on in the same direction after a flick does nothing")
    func sameDirectionAfterFlickIsIgnored() {
        var rig = Rig.swiping()
        var events: [GestureEvent] = []
        events += rig.move(toX: 0.5, toY: 0.70, over: 0.25)
        events += rig.move(toX: 0.5, toY: 0.95, over: 0.30)
        #expect(flicks(in: events) == [.flick(.up)])
    }

    @Test("a sideways bounce works the same way: right, then carry on left past the middle")
    func sidewaysBounce() {
        var rig = Rig.swiping()
        var events: [GestureEvent] = []
        events += rig.move(toX: 0.75, toY: 0.5, over: 0.25)
        events += rig.move(toX: 0.25, toY: 0.5, over: 0.40)
        #expect(swipes(in: events) == [.swipe(.right), .swipe(.left)])
    }

    // Field evidence: the hand rests low in the frame, so there is little room
    // below it. Vertical strokes need a smaller threshold than sideways ones.
    @Test("a small vertical flick is tracked, though a small sideways move is not a swipe")
    func smallVerticalFlickIsTracked() {
        var rig = Rig.swiping()
        let sideways = rig.move(toX: 0.59, toY: 0.5, over: 0.25)
        #expect(swipes(in: sideways).isEmpty)
        rig.hold(for: 0.5)
        let vertical = rig.move(toX: 0.59, toY: 0.59, over: 0.25)
        #expect(flicks(in: vertical) == [.flick(.up)])
    }

    @Test("a small flick down is tracked too")
    func smallFlickDownIsTracked() {
        var rig = Rig.swiping()
        // Reposition slowly: a quick move there would itself be a flick down.
        rig.move(toX: 0.5, toY: 0.30, over: 2.0)
        rig.hold(for: 0.5)
        let down = rig.move(toX: 0.5, toY: 0.21, over: 0.25)
        #expect(flicks(in: down) == [.flick(.down)])
    }
}
