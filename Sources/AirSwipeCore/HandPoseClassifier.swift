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
            return .fist
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

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }
}
