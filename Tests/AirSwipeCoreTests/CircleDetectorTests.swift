import Foundation
import Testing
@testable import AirSwipeCore

@Suite("CircleDetector")
struct CircleDetectorTests {
    private typealias Path = [(t: Double, x: Double, y: Double)]
    private let aspect = 0.75

    /// A circle that is round in the picture: frame heights are scaled by `aspect`, so
    /// the y radius is larger in frame units.
    private func circle(radius: Double, seconds: Double, turns: Double = 1.0,
                        clockwise: Bool = false, start: Double = 0) -> Path {
        let steps = Int(seconds * 30)
        let sign = clockwise ? -1.0 : 1.0
        return (0...steps).map { k in
            let angle = sign * turns * 2 * .pi * Double(k) / Double(steps)
            return (start + Double(k) / 30,
                    0.5 + radius * cos(angle),
                    0.5 + radius * sin(angle) / aspect)
        }
    }

    /// The times at which the detector reported a circle.
    private func firings(_ path: Path) -> [Double] {
        var detector = CircleDetector(config: GestureConfig())
        return path.compactMap { detector.add(x: $0.x, y: $0.y, at: $0.t) ? $0.t : nil }
    }

    @Test("a counter-clockwise circle is a circle, once")
    func counterClockwise() {
        #expect(firings(circle(radius: 0.12, seconds: 1.0)).count == 1)
    }

    @Test("a clockwise circle is a circle too")
    func clockwise() {
        #expect(firings(circle(radius: 0.12, seconds: 1.0, clockwise: true)).count == 1)
    }

    @Test("small and large circles both count")
    func sizes() {
        for radius in [0.06, 0.09, 0.15, 0.20] {
            #expect(firings(circle(radius: radius, seconds: 1.0)).count == 1, "radius \(radius)")
        }
    }

    @Test("fast and unhurried circles both count")
    func speeds() {
        for seconds in [0.6, 1.0, 1.4] {
            #expect(firings(circle(radius: 0.12, seconds: seconds)).count == 1, "\(seconds) s")
        }
    }

    @Test("a circle drawn after the hand rested still counts")
    func afterRest() {
        #expect(firings(circle(radius: 0.12, seconds: 1.0, start: 2.0)).count == 1)
    }

    @Test("one circle fires once, even if the hand keeps going round")
    func firesOnce() {
        #expect(firings(circle(radius: 0.12, seconds: 1.3, turns: 1.3)).count == 1)
    }

    @Test("a second circle after the cooldown fires again")
    func firesAgain() {
        let path = circle(radius: 0.12, seconds: 1.0)
            + circle(radius: 0.12, seconds: 1.0, start: 3.0)
        #expect(firings(path).count == 2)
    }

    @Test("a half circle is not a circle")
    func halfCircle() {
        #expect(firings(circle(radius: 0.12, seconds: 0.5, turns: 0.5)).isEmpty)
    }

    @Test("a circle too slow to finish inside the window is not a circle")
    func slowCircle() {
        #expect(firings(circle(radius: 0.12, seconds: 4.0)).isEmpty)
    }

    @Test("a straight back-and-forth wave is not a circle")
    func wave() {
        let path: Path = (0...90).map { k in
            let t = Double(k) / 30
            return (t, 0.5 + 0.2 * sin(2 * .pi * 1.5 * t), 0.5)
        }
        #expect(firings(path).isEmpty)
    }

    @Test("a diagonal wave is not a circle")
    func diagonalWave() {
        let path: Path = (0...90).map { k in
            let t = Double(k) / 30
            let s = 0.15 * sin(2 * .pi * 1.5 * t)
            return (t, 0.5 + s, 0.5 + s / aspect)
        }
        #expect(firings(path).isEmpty)
    }

    // Not a figure of eight: its first loop is itself a round loop, and a detector that
    // decides as the hand moves cannot know a second, cancelling loop is coming.
    @Test("a zigzag squiggle that never closes a loop is not a circle")
    func squiggle() {
        let path: Path = (0...36).map { k in
            let t = Double(k) / 30
            let progress = Double(k) / 36
            return (t, 0.3 + 0.4 * progress, 0.5 + 0.06 * sin(2 * .pi * 2 * progress) / aspect)
        }
        #expect(firings(path).isEmpty)
    }

    @Test("a small wobble is not a circle")
    func smallWobble() {
        #expect(firings(circle(radius: 0.02, seconds: 1.0)).isEmpty)
    }

    @Test("a still hand with jitter is not a circle")
    func jitter() {
        let path: Path = (0...120).map { k in
            let t = Double(k) / 30
            return (t, 0.5 + 0.004 * sin(7 * t), 0.5 + 0.004 * cos(11 * t))
        }
        #expect(firings(path).isEmpty)
    }
}
