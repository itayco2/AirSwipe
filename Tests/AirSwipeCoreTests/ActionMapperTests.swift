import Testing
import AirSwipeCore

@Suite("ActionMapper")
struct ActionMapperTests {
    @Test("a swipe right goes back, like a trackpad swipe moving the page right")
    func swipeRightIsBack() {
        let mapper = ActionMapper()
        #expect(mapper.actions(for: .swipe(.right)) == [.back])
    }

    @Test("a swipe left goes forward")
    func swipeLeftIsForward() {
        let mapper = ActionMapper()
        #expect(mapper.actions(for: .swipe(.left)) == [.forward])
    }

    @Test("arming and disarming produce no action")
    func armedAndDisarmedAreSilent() {
        let mapper = ActionMapper()
        #expect(mapper.actions(for: .armed).isEmpty)
        #expect(mapper.actions(for: .disarmed).isEmpty)
    }

    @Test("a scroll amount becomes whole pixels at the configured speed")
    func scrollBecomesPixels() {
        let mapper = ActionMapper(maxScrollPixelsPerSecond: 1200)
        // 0.0255 s at full speed x 1200 px/s = 30.6 px, so 30 whole pixels.
        #expect(mapper.actions(for: .scroll(amount: 0.0255)) == [.scroll(pixels: 30)])
    }

    @Test("scrolling down gives negative pixels")
    func scrollDownIsNegative() {
        let mapper = ActionMapper(maxScrollPixelsPerSecond: 1200)
        #expect(mapper.actions(for: .scroll(amount: -0.0255)) == [.scroll(pixels: -30)])
    }

    @Test("sub-pixel scroll amounts accumulate instead of being lost")
    func subPixelAmountsAccumulate() {
        let mapper = ActionMapper(maxScrollPixelsPerSecond: 1200)
        // 0.0004 x 1200 = 0.48 px per event; five events carry 2.4 px in total.
        var total: Int32 = 0
        for _ in 0..<5 {
            for case .scroll(let pixels) in mapper.actions(for: .scroll(amount: 0.0004)) {
                total += pixels
            }
        }
        #expect(total == 2)
    }

    @Test("a pending fraction does not leak across a disarm")
    func remainderResetsOnDisarm() {
        let mapper = ActionMapper(maxScrollPixelsPerSecond: 1200)
        _ = mapper.actions(for: .scroll(amount: 0.0004))
        _ = mapper.actions(for: .scroll(amount: 0.0004))
        _ = mapper.actions(for: .disarmed)
        // Without the reset this would be 0.96 + 0.48 = 1.44 px, i.e. one pixel.
        #expect(mapper.actions(for: .scroll(amount: 0.0004)).isEmpty)
    }

    // Starting needs more than stopping (the message box must be focused first), so the
    // mapper says which one it is instead of a bare toggle.
    @Test("the first circle starts voice, the next stops it, and so on")
    func circlesAlternate() {
        let mapper = ActionMapper()
        #expect(mapper.voiceActive == false)
        #expect(mapper.actions(for: .circle) == [.startVoice])
        #expect(mapper.voiceActive == true)
        #expect(mapper.actions(for: .circle) == [.stopVoice])
        #expect(mapper.voiceActive == false)
        #expect(mapper.actions(for: .circle) == [.startVoice])
    }

    // Dictation needs a moment to finish typing after it stops, so a send that follows a
    // running dictation asks for the stop first; the sink spaces the two out.
    @Test("send presses send, and stops dictation first if it was running")
    func sendStopsDictationFirst() {
        let mapper = ActionMapper()
        #expect(mapper.actions(for: .send) == [.sendMessage])

        _ = mapper.actions(for: .circle)
        #expect(mapper.voiceActive)
        #expect(mapper.actions(for: .send) == [.stopVoice, .sendMessage])
        #expect(mapper.voiceActive == false)
        #expect(mapper.actions(for: .send) == [.sendMessage])
    }

    @Test("arming or disarming forgets that voice was running")
    func voiceResetsWithTheEngine() {
        let mapper = ActionMapper()
        _ = mapper.actions(for: .circle)
        _ = mapper.actions(for: .disarmed)
        #expect(mapper.voiceActive == false)
        #expect(mapper.actions(for: .circle) == [.startVoice])
        _ = mapper.actions(for: .armed)
        #expect(mapper.voiceActive == false)
    }
}
