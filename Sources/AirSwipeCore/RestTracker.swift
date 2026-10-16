import Foundation

/// Tracks where the hand last came to rest, which is where a flick starts from.
///
/// A flick is a quick move away from a hand that was still. Measuring from that rest
/// position, rather than from the highest and lowest points of the last moment, keeps
/// two things from looking like flicks. A pose flicker shifts the hand's reading by a
/// few hundredths one way and then the other; seen from the rest position it is half
/// the size, below the flick distance. And the rebound after a return starts from a
/// turnaround, which is never a rest.
///
/// Internal to the engine, like `CircleDetector`: the engine feeds it every armed frame.
struct RestTracker {
    private let radius: Double
    private let duration: Double
    private let moveWindow: Double

    // The hand has stayed within `radius` of this spot since `stillSince`. The spot
    // moves with the hand whenever it strays, so it only ever describes the latest stillness.
    private var stillX = 0.0
    private var stillY = 0.0
    private var stillSince: TimeInterval = 0
    private var started = false

    /// Where the hand last rested. It stays until the hand has been away from there
    /// longer than `moveWindow`, because a move that slow is a drift and not a flick.
    private(set) var origin: (x: Double, y: Double)?
    private var lastNearOrigin: TimeInterval = 0

    /// True while the hand is resting at `origin`.
    private(set) var isAtRest = false

    init(config: GestureConfig) {
        radius = config.flickRestRadius
        duration = config.flickRestDuration
        moveWindow = config.flickMoveWindow
    }

    /// Feed one frame.
    mutating func update(x: Double, y: Double, at time: TimeInterval) {
        guard started else {
            restart(x: x, y: y, at: time)
            return
        }

        if hypot(x - stillX, y - stillY) > radius {
            stillX = x
            stillY = y
            stillSince = time
        }
        if time - stillSince >= duration {
            // Resting here. If that is somewhere new, this is where a flick starts from now.
            let isNewSpot = origin.map { hypot(stillX - $0.x, stillY - $0.y) > radius } ?? true
            if isNewSpot {
                origin = (stillX, stillY)
                lastNearOrigin = time
            }
        }

        guard let spot = origin else {
            isAtRest = false
            return
        }
        if hypot(x - spot.x, y - spot.y) <= radius {
            lastNearOrigin = time
            isAtRest = true
        } else {
            isAtRest = false
            if time - lastNearOrigin > moveWindow {
                origin = nil
            }
        }
    }

    /// Forget the rest and start counting stillness again from here. Called after a stroke,
    /// so the move that just fired cannot count as part of the next one.
    mutating func restart(x: Double, y: Double, at time: TimeInterval) {
        stillX = x
        stillY = y
        stillSince = time
        started = true
        origin = nil
        isAtRest = false
    }

    /// Forget everything, for when the hand is lost.
    mutating func reset() {
        started = false
        origin = nil
        isAtRest = false
    }
}
