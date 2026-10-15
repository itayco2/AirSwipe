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

    init(config: GestureConfig = GestureConfig()) {
        engine = GestureEngine(config: config)
    }

    /// Keep the hand where it is (or at an explicit spot) for `seconds`.
    @discardableResult
    mutating func hold(x newX: Double? = nil, y newY: Double? = nil,
                       for seconds: Double, open: Bool = true) -> [GestureEvent] {
        move(toX: newX ?? x, toY: newY ?? y, over: seconds, open: open)
    }

    /// Glide in a straight line to (toX, toY) over `seconds`.
    @discardableResult
    mutating func move(toX: Double, toY: Double, over seconds: Double,
                       open: Bool = true) -> [GestureEvent] {
        let frames = max(1, Int((seconds * fps).rounded()))
        let (startX, startY) = (x, y)
        var events: [GestureEvent] = []
        for frame in 1...frames {
            let t = Double(frame) / Double(frames)
            x = startX + (toX - startX) * t
            y = startY + (toY - startY) * t
            time += 1 / fps
            events += engine.process(HandSample(x: x, y: y, isOpen: open), at: time)
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
}

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

    @Test("a closed fist never arms, even held still")
    func fistDoesNotArm() {
        var rig = Rig()
        let fist = rig.hold(for: 1.0, open: false)
        #expect(fist.isEmpty)
        let open = rig.hold(for: 0.8)
        #expect(open == [.armed])
    }
}

extension Rig {
    /// A rig whose engine is already armed, with the hand resting mid-frame.
    static func armed(config: GestureConfig = GestureConfig()) -> Rig {
        var rig = Rig(config: config)
        rig.hold(for: 0.8)
        return rig
    }
}

/// Only the swipe events, so a test can ignore scrolling that a move also causes.
private func swipes(in events: [GestureEvent]) -> [GestureEvent] {
    events.filter {
        if case .swipe = $0 { return true }
        return false
    }
}

@Suite("Swipe")
struct SwipeTests {
    @Test("a fast move to the right emits swipe right")
    func swipeRight() {
        var rig = Rig.armed()
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: events) == [.swipe(.right)])
    }

    @Test("a fast move to the left emits swipe left")
    func swipeLeft() {
        var rig = Rig.armed()
        let events = rig.move(toX: 0.20, toY: 0.5, over: 0.2)
        #expect(swipes(in: events) == [.swipe(.left)])
    }

    @Test("a fast move while not armed does nothing, and arming still works afterward")
    func notArmedNoSwipe() {
        var rig = Rig()
        let events = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(events.isEmpty)
        let settled = rig.hold(for: 0.8)
        #expect(settled == [.armed])
    }

    @Test("a mostly vertical flick is not a swipe, but a horizontal one afterward is")
    func verticalFlickIgnored() {
        var rig = Rig.armed()
        let flick = rig.move(toX: 0.70, toY: 0.90, over: 0.2)
        #expect(swipes(in: flick).isEmpty)
        rig.hold(for: 0.5)
        let real = rig.move(toX: 0.30, toY: 0.90, over: 0.2)
        #expect(swipes(in: real) == [.swipe(.left)])
    }

    @Test("a slow drift is not a swipe, but a quick move afterward is")
    func slowDriftIgnored() {
        var rig = Rig.armed()
        let drift = rig.move(toX: 0.90, toY: 0.5, over: 2.0)
        #expect(swipes(in: drift).isEmpty)
        let quick = rig.move(toX: 0.50, toY: 0.5, over: 0.2)
        #expect(swipes(in: quick) == [.swipe(.left)])
    }

    @Test("the return stroke right after a swipe is ignored; a later deliberate swipe fires")
    func returnStrokeIgnored() {
        var rig = Rig.armed()
        let first = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: first) == [.swipe(.right)])
        let back = rig.move(toX: 0.50, toY: 0.5, over: 0.2)
        #expect(swipes(in: back).isEmpty)
        rig.hold(for: 0.8)
        let second = rig.move(toX: 0.20, toY: 0.5, over: 0.2)
        #expect(swipes(in: second) == [.swipe(.left)])
    }
}

/// Only the scroll amounts, in order.
private func scrolls(in events: [GestureEvent]) -> [Double] {
    events.compactMap {
        if case .scroll(let amount) = $0 { return amount }
        return nil
    }
}

@Suite("Scroll")
struct ScrollTests {
    @Test("raising the hand past the dead zone scrolls up")
    func raisedHandScrollsUp() {
        var rig = Rig.armed()
        let amounts = scrolls(in: rig.hold(y: 0.80, for: 0.5))
        #expect(!amounts.isEmpty)
        #expect(amounts.allSatisfy { $0 > 0 })
    }

    @Test("lowering the hand past the dead zone scrolls down")
    func loweredHandScrollsDown() {
        var rig = Rig.armed()
        let amounts = scrolls(in: rig.hold(y: 0.20, for: 0.5))
        #expect(!amounts.isEmpty)
        #expect(amounts.allSatisfy { $0 < 0 })
    }

    @Test("a hand resting inside the dead zone does not scroll, but raising it does")
    func deadZone() {
        var rig = Rig.armed()
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
            var rig = Rig.armed()
            rig.move(toX: 0.5, toY: 0.5 + offset, over: 0.3)
            return scrolls(in: rig.hold(for: 0.3)).last ?? 0
        }
        let dt = 1.0 / 30.0
        #expect(abs(steadyAmount(offset: 0.12) - 0.25 * dt) < 1e-9)
        #expect(abs(steadyAmount(offset: 0.24) - 0.75 * dt) < 1e-9)
        #expect(abs(steadyAmount(offset: 0.40) - 1.00 * dt) < 1e-9)
    }

    @Test("scrolling pauses while a swipe cools down, then resumes")
    func noScrollDuringSwipeCooldown() {
        var rig = Rig.armed()
        rig.move(toX: 0.5, toY: 0.8, over: 0.3)
        rig.hold(for: 0.5)
        let swipe = rig.move(toX: 0.8, toY: 0.8, over: 0.2)
        #expect(swipes(in: swipe) == [.swipe(.right)])
        let cooling = rig.hold(for: 0.4)
        #expect(scrolls(in: cooling).isEmpty)
        let resumed = rig.hold(for: 0.8)
        #expect(!scrolls(in: resumed).isEmpty)
    }
}

@Suite("Disarm")
struct DisarmTests {
    @Test("a fist held past the threshold disarms")
    func fistDisarms() {
        var rig = Rig.armed()
        let events = rig.hold(for: 0.5, open: false)
        #expect(events == [.disarmed])
    }

    @Test("a brief closed flicker does not disarm")
    func briefFistIgnored() {
        var rig = Rig.armed()
        let flicker = rig.hold(for: 0.1, open: false)
        #expect(flicker.isEmpty)
        let swipe = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: swipe) == [.swipe(.right)])
    }

    @Test("losing the hand for a second disarms")
    func handLostDisarms() {
        var rig = Rig.armed()
        let events = rig.noHand(for: 1.2)
        #expect(events == [.disarmed])
    }

    @Test("a short dropout does not disarm")
    func shortDropoutIgnored() {
        var rig = Rig.armed()
        let dropout = rig.noHand(for: 0.5)
        #expect(dropout.isEmpty)
        let swipe = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: swipe) == [.swipe(.right)])
    }

    @Test("holding still with no gesture past the idle timeout disarms")
    func idleDisarms() {
        var rig = Rig.armed()
        let events = rig.hold(for: 7.0)
        #expect(events == [.disarmed])
    }

    @Test("gesture activity resets the idle timer")
    func activityResetsIdle() {
        var rig = Rig.armed()
        rig.hold(for: 4.0)
        let swipe = rig.move(toX: 0.80, toY: 0.5, over: 0.2)
        #expect(swipes(in: swipe) == [.swipe(.right)])
        let later = rig.hold(for: 4.0)
        #expect(later.isEmpty)
    }

    @Test("after an idle timeout the hand must be lowered before it can arm again")
    func idleDisarmRequiresRelease() {
        var rig = Rig.armed()
        let idle = rig.hold(for: 8.0)
        #expect(idle == [.disarmed])
        rig.noHand(for: 0.3)
        let rearmed = rig.hold(for: 0.8)
        #expect(rearmed == [.armed])
    }

    @Test("after a fist disarm, fast moves do nothing until the palm is held still again")
    func disarmedIgnoresSwipes() {
        var rig = Rig.armed()
        rig.hold(for: 0.5, open: false)
        let moving = rig.move(toX: 0.90, toY: 0.5, over: 0.2)
        #expect(moving.isEmpty)
        let again = rig.hold(for: 0.8)
        #expect(again == [.armed])
    }

    @Test("re-arming sets a new neutral height")
    func rearmResetsNeutral() {
        var rig = Rig.armed()
        rig.hold(for: 0.5, open: false)
        rig.move(toX: 0.5, toY: 0.8, over: 0.2)
        let rearmed = rig.hold(for: 0.8)
        #expect(rearmed == [.armed])
        let resting = rig.hold(for: 0.5)
        #expect(scrolls(in: resting).isEmpty)
    }
}
