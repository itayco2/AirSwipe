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

    // MARK: Loops recorded from a real camera (live run, 2026-10-16, 10 samples a second)
    //
    // The stop circle did not stop dictation, and two start circles did nothing. Replaying
    // the log showed these were real loops (a full turn, about 0.3 across, 1.3 s) that the
    // old roundness test rejected, because it measured from the middle of everything in
    // the last 1.5 s, including the hand resting before and after the loop.

    @Test("a real stop circle, drawn from rest with the hand parked mid-loop afterwards")
    func recordedStopCircle() {
        let path: Path = [
            (43.0, 0.59, 0.36), (43.1, 0.59, 0.36), (43.2, 0.59, 0.34), (43.3, 0.55, 0.30),
            (43.4, 0.46, 0.28), (43.5, 0.42, 0.30), (43.6, 0.38, 0.35), (43.7, 0.39, 0.49),
            (43.8, 0.46, 0.59), (43.9, 0.52, 0.64), (44.0, 0.61, 0.66), (44.1, 0.67, 0.59),
            (44.2, 0.72, 0.50), (44.3, 0.73, 0.39), (44.4, 0.70, 0.28), (44.5, 0.68, 0.21),
            (44.6, 0.52, 0.19), (44.7, 0.49, 0.23), (44.8, 0.47, 0.34), (44.9, 0.48, 0.39),
            (45.0, 0.50, 0.38), (45.1, 0.51, 0.36), (45.2, 0.52, 0.37), (45.3, 0.52, 0.37),
            (45.4, 0.53, 0.36), (45.5, 0.55, 0.28), (45.6, 0.36, 0.22),
        ]
        #expect(firings(path).count == 1)
    }

    @Test("a real loop that ends with the hand resting in the middle of it")
    func recordedLoopEndingAtRest() {
        let path: Path = [
            (24.4, 0.56, 0.35), (24.5, 0.56, 0.35), (24.6, 0.56, 0.35), (24.7, 0.57, 0.35),
            (24.8, 0.57, 0.35), (24.9, 0.58, 0.35), (25.0, 0.58, 0.35), (25.1, 0.58, 0.35),
            (25.2, 0.58, 0.35), (25.3, 0.58, 0.36),
            (25.4, 0.59, 0.34), (25.5, 0.60, 0.29), (25.6, 0.51, 0.28), (25.7, 0.45, 0.21),
            (25.8, 0.41, 0.32), (25.9, 0.39, 0.45), (26.0, 0.48, 0.55), (26.2, 0.59, 0.59),
            (26.3, 0.67, 0.53), (26.4, 0.71, 0.46), (26.5, 0.72, 0.37), (26.6, 0.69, 0.31),
            (26.7, 0.64, 0.26), (26.8, 0.59, 0.24), (26.9, 0.54, 0.28), (27.0, 0.53, 0.29),
            (27.1, 0.53, 0.31), (27.2, 0.54, 0.32), (27.3, 0.55, 0.32), (27.4, 0.55, 0.33),
            (27.5, 0.55, 0.33), (27.6, 0.55, 0.33), (27.7, 0.56, 0.33), (27.8, 0.56, 0.33),
            (27.9, 0.56, 0.33),
        ]
        #expect(firings(path).count == 1)
    }

    @Test("a real loop that starts from a wide swing of the hand")
    func recordedLoopAfterASwing() {
        let path: Path = [
            (27.9, 0.56, 0.33), (28.0, 0.56, 0.33), (28.1, 0.56, 0.33), (28.2, 0.57, 0.33),
            (28.3, 0.57, 0.33), (28.4, 0.57, 0.34), (28.5, 0.57, 0.34), (28.6, 0.57, 0.34),
            (28.7, 0.59, 0.36), (28.8, 0.67, 0.38), (28.9, 0.73, 0.29),
            (29.0, 0.72, 0.25), (29.2, 0.43, 0.08), (29.3, 0.38, 0.12), (29.4, 0.32, 0.29),
            (29.5, 0.37, 0.44), (29.6, 0.42, 0.54), (29.7, 0.50, 0.59), (29.8, 0.58, 0.60),
            (29.9, 0.66, 0.56), (30.0, 0.70, 0.48), (30.1, 0.72, 0.38), (30.2, 0.69, 0.30),
            (30.3, 0.64, 0.23), (30.4, 0.59, 0.24), (30.5, 0.54, 0.28), (30.6, 0.53, 0.29),
            (30.7, 0.54, 0.29), (30.8, 0.55, 0.29), (30.9, 0.56, 0.29), (31.0, 0.55, 0.29),
            (31.1, 0.56, 0.30), (31.2, 0.56, 0.29), (31.3, 0.56, 0.29),
        ]
        #expect(firings(path).count == 1)
    }

    @Test("two real start circles that did work still work")
    func recordedStartCircles() {
        let first: Path = [
            (14.0, 0.65, 0.27), (14.2, 0.59, 0.21), (14.3, 0.45, 0.26), (14.4, 0.41, 0.25),
            (14.5, 0.37, 0.29), (14.6, 0.36, 0.42), (14.8, 0.40, 0.53), (14.9, 0.45, 0.60),
            (15.0, 0.54, 0.62), (15.1, 0.61, 0.59), (15.3, 0.68, 0.50), (15.4, 0.72, 0.40),
            (15.5, 0.70, 0.30), (15.6, 0.65, 0.26), (15.7, 0.59, 0.23), (15.9, 0.54, 0.28),
            (16.0, 0.53, 0.32),
        ]
        let second: Path = [
            (38.0, 0.64, 0.37), (38.1, 0.63, 0.34), (38.2, 0.58, 0.29), (38.3, 0.49, 0.27),
            (38.4, 0.45, 0.30), (38.5, 0.39, 0.40), (38.6, 0.42, 0.51), (38.7, 0.48, 0.56),
            (38.8, 0.57, 0.59), (38.9, 0.64, 0.56), (39.0, 0.68, 0.48), (39.1, 0.68, 0.40),
            (39.2, 0.64, 0.32), (39.3, 0.59, 0.29), (39.4, 0.55, 0.29), (39.5, 0.53, 0.33),
            (39.6, 0.54, 0.34), (39.7, 0.55, 0.34), (39.8, 0.56, 0.34), (39.9, 0.56, 0.35),
            (40.0, 0.57, 0.35),
        ]
        #expect(firings(first).count == 1)
        #expect(firings(second).count == 1)
    }

    @Test("a circle drawn after the hand moved in from the side still counts")
    func loopAfterApproach() {
        let approach: Path = (0...15).map { k in
            let u = Double(k) / 15
            return (Double(k) / 30, 0.9 - 0.4 * u, 0.5)
        }
        let loop = circle(radius: 0.12, seconds: 1.0, start: 0.6)
        #expect(firings(approach + loop).count == 1)
    }

    @Test("a sloppy circle, off round by a third, still counts")
    func sloppyCircle() {
        let steps = 30
        let path: Path = (0...steps).map { k in
            let angle = 2 * Double.pi * Double(k) / Double(steps)
            let radius = 0.13 * (1 + 0.3 * sin(2 * angle))
            return (Double(k) / 30, 0.5 + radius * cos(angle), 0.5 + radius * sin(angle) / aspect)
        }
        #expect(firings(path).count == 1)
    }

    // Aimless wandering sometimes turns through a full circle's worth of angle, but it
    // winds open: the hand ends far from where the turn began. A drawn circle closes.
    @Test("a coil that travels sideways as it turns never closes, so it is not a circle")
    func coil() {
        let steps = 36
        let path: Path = (0...steps).map { k in
            let u = Double(k) / Double(steps)
            return (Double(k) / 30,
                    0.25 + 0.25 * u + 0.12 * cos(2 * .pi * u),
                    0.5 + 0.12 * sin(2 * .pi * u) / aspect)
        }
        #expect(firings(path).isEmpty)
    }
}
