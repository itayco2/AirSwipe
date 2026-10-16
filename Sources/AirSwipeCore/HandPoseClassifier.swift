import Foundation

/// Reads a `HandPose` from the finger joints.
///
/// Kept free of Vision types so the geometry can be tested with plain points.
public enum HandPoseClassifier {
    private enum Finger {
        case extended
        case curled
        case undecided
    }

    /// How straight a finger is: the distance from its first to its last joint,
    /// divided by the length of the chain. 1 is perfectly straight; a curled finger
    /// folds back on itself and scores much lower.
    ///
    /// It needs only the finger's own joints. No wrist, palm width or camera
    /// distance is involved, so it keeps working when the hand is low in the frame
    /// and the wrist is out of view, and when the hand is rotated or far away.
    public static func straightness(of chain: [CGPoint]) -> Double? {
        guard chain.count >= 2 else { return nil }

        var length = 0.0
        for (a, b) in zip(chain, chain.dropFirst()) {
            length += distance(a, b)
        }
        guard length > 0 else { return nil }
        return distance(chain[0], chain[chain.count - 1]) / length
    }

    /// - Parameters:
    ///   - fingers: the four fingers, index to little. Each is its joints from the
    ///     knuckle to the fingertip. A finger with a joint missing is passed as an
    ///     empty array, and the hand then cannot be a pose. The thumb is ignored:
    ///     it varies too much between people and poses.
    ///   - extendedStraightness: at or above this a finger counts as extended.
    ///     Extended fingers measured 0.98 to 1.00.
    ///   - curledStraightness: at or below this a finger counts as curled. Nothing
    ///     that was not extended measured above 0.86. The gap between the two is
    ///     undecided, which keeps a half-bent finger from flickering between poses.
    public static func classify(fingers: [[CGPoint]],
                                thumb: [CGPoint] = [],
                                extendedStraightness: Double = 0.92,
                                curledStraightness: Double = 0.88) -> HandPose {
        guard fingers.count == 4 else { return .other }

        let states = fingers.map { chain -> Finger in
            guard let straight = straightness(of: chain) else { return .undecided }
            if straight >= extendedStraightness { return .extended }
            if straight <= curledStraightness { return .curled }
            return .undecided
        }

        switch (states[0], states[1], states[2], states[3]) {
        case (.extended, .extended, .extended, .extended):
            return .openPalm
        case (.curled, .curled, .curled, .curled):
            // A fist, unless the thumb sticks straight up: then it is a thumbs up. They
            // must be told apart because a held fist stops AirSwipe and a held thumbs up
            // sends. A thumb that is folded, bent, sideways, down or unseen stays a fist.
            return isThumbUp(thumb) && curledTightly(fingers) ? .thumbsUp : .fist
        // The little finger does not decide between one finger and two. It is short,
        // often hidden behind the others, and often left sticking out: in a real run
        // it alone turned a clear one-finger hand into `.other` about a third of the
        // time. The index, middle and ring fingers are what tell the poses apart.
        case (.extended, .curled, .curled, _):
            return .oneFinger
        case (.extended, .extended, .curled, _):
            return .twoFingers
        default:
            return .other
        }
    }

    /// How straight the thumb must be to count as pointing out. Measured on one user
    /// (dry run, 2026-10-16): a deliberate thumbs up read 0.96 to 1.00, while a relaxed
    /// fist with the thumb loosely up read 0.90 to 0.95, so the line sits between them.
    /// Tune from `--debug`, which prints the thumb's straightness and direction.
    static let thumbExtendedStraightness = 0.95

    /// How far from straight up the thumb may lean, as the cosine of the angle: 0.8 is
    /// about 37 degrees. Deliberate thumbs up read 0.95 to 0.99 (under 20 degrees).
    static let thumbUpCosine = 0.8

    /// A thumbs up squeezes the other four fingers tightly to hold the thumb up, while a
    /// relaxed fist leaves them looser. The average straightness of the four fingers
    /// must be at or below this. Measured on one user: thumbs up held about 0.2 (rarely
    /// above 0.4), relaxed fist 0.64 to 0.74. This is the main guard against a fist
    /// being read as a thumbs up, which would send a message by accident.
    static let thumbsUpFingerStraightness = 0.50

    /// True when all four fingers are seen and curl tightly on average.
    private static func curledTightly(_ fingers: [[CGPoint]]) -> Bool {
        let values = fingers.compactMap { straightness(of: $0) }
        guard values.count == fingers.count, !values.isEmpty else { return false }
        return values.reduce(0, +) / Double(values.count) <= thumbsUpFingerStraightness
    }

    /// The thumb chain runs base (CMC) to tip. It is "up" when it is straight and its
    /// base-to-tip direction is within about 37 degrees of vertical (y grows upward).
    /// An unseen thumb (empty chain) is never up.
    public static func isThumbUp(_ thumb: [CGPoint]) -> Bool {
        guard let base = thumb.first, let tip = thumb.last, thumb.count >= 2,
              let straight = straightness(of: thumb), straight >= thumbExtendedStraightness else {
            return false
        }
        let dx = Double(tip.x - base.x)
        let dy = Double(tip.y - base.y)
        let length = hypot(dx, dy)
        return length > 0 && dy / length >= thumbUpCosine
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }
}
