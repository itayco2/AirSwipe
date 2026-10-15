import Foundation

/// Decides from joint positions whether a hand is an open palm.
///
/// Kept free of Vision types so the geometry can be tested with plain points.
public enum OpenPalmClassifier {
    /// An open palm has all four fingers extended: each fingertip sits clearly
    /// farther from the wrist than its own knuckle does. Curling a finger pulls
    /// its tip back toward the wrist, so one curled finger is enough to fail.
    /// The thumb is ignored: it varies too much between people and poses.
    ///
    /// - Parameters:
    ///   - wrist: the wrist joint.
    ///   - knuckles: the four finger-base joints (index to little finger).
    ///   - fingertips: the four fingertip joints, in the same order.
    ///   - extensionRatio: how much farther than its knuckle a fingertip must
    ///     sit from the wrist to count as extended.
    public static func isOpen(wrist: CGPoint, knuckles: [CGPoint], fingertips: [CGPoint],
                              extensionRatio: Double = 1.4) -> Bool {
        guard knuckles.count == 4, fingertips.count == 4 else { return false }

        for (knuckle, tip) in zip(knuckles, fingertips) {
            let knuckleDistance = distance(wrist, knuckle)
            guard knuckleDistance > 0 else { return false }
            if distance(wrist, tip) < extensionRatio * knuckleDistance {
                return false
            }
        }
        return true
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }
}
