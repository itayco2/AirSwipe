import Foundation

/// Recognizes a hand drawing a circle in the air.
///
/// Pure and clock-free like the rest of the core: positions arrive with timestamps. A
/// circle is a path that, within `circleWindow`, turns through nearly a full turn in
/// one direction around its own centre, is wide and tall enough to be deliberate, and
/// stays round. A back-and-forth wave turns by about zero and a figure of eight cancels
/// itself, so neither counts.
struct CircleDetector {
    private let config: GestureConfig
    private var points: [(time: Double, x: Double, y: Double)] = []
    private var lastFire = -Double.infinity

    /// Positions closer than this to the last kept one are dropped, so a hand at rest
    /// adds no points and cannot pull the centre of the path off the circle.
    private let minStep = 0.004
    private let minPoints = 8

    init(config: GestureConfig) {
        self.config = config
    }

    mutating func reset() {
        points.removeAll()
    }

    /// Feed one position. Returns true at the moment a circle is completed.
    mutating func add(x: Double, y: Double, at time: Double) -> Bool {
        let scaledY = y * config.circleAspectRatio
        if let last = points.last, hypot(x - last.x, scaledY - last.y) < minStep {
            return false
        }
        points.append((time, x, scaledY))
        points.removeAll { time - $0.time > config.circleWindow }

        guard time - lastFire >= config.circleCooldown,
              points.count >= minPoints,
              isCircle() else { return false }
        points.removeAll()
        lastFire = time
        return true
    }

    /// The loop is the end of the path, so test every stretch of the path that ends now,
    /// longest first. What came before the loop (the hand moving into position, resting
    /// in the middle of where the loop will be) must not spoil the measurement: in a live
    /// run it did, and real loops of a full turn were rejected as "not round".
    private func isCircle() -> Bool {
        var start = 0
        while points.count - start >= minPoints {
            if looksLikeCircle(points[start...]) { return true }
            start += 1
        }
        return false
    }

    private func looksLikeCircle(_ path: ArraySlice<(time: Double, x: Double, y: Double)>) -> Bool {
        let count = Double(path.count)
        let centerX = path.reduce(0) { $0 + $1.x } / count
        let centerY = path.reduce(0) { $0 + $1.y } / count

        // Big enough to be deliberate: wide and tall.
        let xs = path.map(\.x)
        let ys = path.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(),
              maxX - minX >= config.circleMinSize,
              maxY - minY >= config.circleMinSize else { return false }

        // Round: most points sit at a similar distance from the centre. The nearest and
        // farthest tenth are ignored, so one stray sample does not decide it.
        let radii = path.map { hypot($0.x - centerX, $0.y - centerY) }.sorted()
        let near = radii[Int(Double(radii.count - 1) * 0.1)]
        let far = radii[Int(Double(radii.count - 1) * 0.9)]
        guard far > 0, near / far >= config.circleMinRoundness else { return false }

        // Turning: add up the signed angle between neighbouring points around the
        // centre. A circle gives about +-2 pi; a wave or a figure of eight cancels out.
        var turn = 0.0
        var travelled = 0.0
        var previous = atan2(path[path.startIndex].y - centerY, path[path.startIndex].x - centerX)
        for point in path.dropFirst() {
            let angle = atan2(point.y - centerY, point.x - centerX)
            var delta = angle - previous
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            turn += delta
            travelled += abs(delta)
            previous = angle
        }
        // Closed: a drawn circle ends near where it began, within one radius (a 315 degree
        // arc ends 0.77 radii away). Aimless wandering that happens to turn far enough
        // winds open instead; in a simulation it ended about 1.3 radii away on average,
        // where the real loops recorded from a camera ended 0.6 to 0.84 away.
        let first = path[path.startIndex]
        let last = path[path.endIndex - 1]
        let meanRadius = radii.reduce(0, +) / count
        guard hypot(last.x - first.x, last.y - first.y) <= meanRadius else { return false }

        // Mostly one direction: wobble may not make up more than 60% extra travel.
        return abs(turn) >= config.circleMinTurn && travelled <= 1.6 * abs(turn)
    }
}
