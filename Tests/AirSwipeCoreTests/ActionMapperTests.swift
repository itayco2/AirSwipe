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
}
