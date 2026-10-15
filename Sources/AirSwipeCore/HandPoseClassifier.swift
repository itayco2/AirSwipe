import Foundation

/// Reads a `HandPose` from joint positions.
///
/// Kept free of Vision types so the geometry can be tested with plain points.
public enum HandPoseClassifier {
    private enum Finger {
        case extended
        case curled
        case undecided
    }

    /// Each finger is judged by how far its tip sits from the wrist compared with
    /// its own knuckle: well past it is extended, back at it is curled, and in
    /// between is undecided. Requiring a clear gap between "extended" and
    /// "curled" is what keeps a half-relaxed hand from flickering between poses.
    /// The thumb is ignored: it varies too much between people and poses.
    ///
    /// - Parameters:
    ///   - wrist: the wrist joint.
    ///   - knuckles: the four finger-base joints (index to little finger).
    ///   - fingertips: the four fingertip joints, in the same order.
    ///   - extendedRatio: tip-to-wrist over knuckle-to-wrist at or above which a
    ///     finger counts as extended.
    ///   - curledRatio: the ratio at or below which a finger counts as curled.
    public static func classify(wrist: CGPoint, knuckles: [CGPoint], fingertips: [CGPoint],
                                extendedRatio: Double = 1.4,
                                curledRatio: Double = 1.1) -> HandPose {
        guard knuckles.count == 4, fingertips.count == 4 else { return .other }

        let fingers = zip(knuckles, fingertips).map { knuckle, tip -> Finger in
            let base = distance(wrist, knuckle)
            guard base > 0 else { return .undecided }
            let ratio = distance(wrist, tip) / base
            if ratio >= extendedRatio { return .extended }
            if ratio <= curledRatio { return .curled }
            return .undecided
        }

        switch (fingers[0], fingers[1], fingers[2], fingers[3]) {
        case (.extended, .extended, .extended, .extended):
            return .openPalm
        case (.curled, .curled, .curled, .curled):
            return .fist
        case (.extended, .curled, .curled, .curled):
            return .oneFinger
        case (.extended, .extended, .curled, .curled):
            return .twoFingers
        default:
            return .other
        }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }
}
