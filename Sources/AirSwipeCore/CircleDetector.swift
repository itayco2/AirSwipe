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

    private func isCircle() -> Bool {
        let count = Double(points.count)
        let centerX = points.reduce(0) { $0 + $1.x } / count
        let centerY = points.reduce(0) { $0 + $1.y } / count

        // Big enough to be deliberate: wide and tall.
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(),
              maxX - minX >= config.circleMinSize,
              maxY - minY >= config.circleMinSize else { return false }

        // Round: no point strays much nearer the centre than the farthest one.
        let radii = points.map { hypot($0.x - centerX, $0.y - centerY) }
        guard let nearest = radii.min(), let farthest = radii.max(), farthest > 0,
              nearest / farthest >= config.circleMinRoundness else { return false }

        // Turning: add up the signed angle between neighbouring points around the
        // centre. A circle gives about +-2 pi; a wave or a figure of eight cancels out.
        var turn = 0.0
        var travelled = 0.0
        var previous = atan2(points[0].y - centerY, points[0].x - centerX)
        for point in points.dropFirst() {
            let angle = atan2(point.y - centerY, point.x - centerX)
            var delta = angle - previous
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            turn += delta
            travelled += abs(delta)
            previous = angle
        }
        // Mostly one direction: wobble may not make up more than 60% extra travel.
        return abs(turn) >= config.circleMinTurn && travelled <= 1.6 * abs(turn)
    }
}
