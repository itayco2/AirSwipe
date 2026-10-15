import AirSwipeCore
import CoreGraphics
import Vision

/// Finds one hand in a camera frame and reduces it to a `HandSample`.
///
/// Everything beyond joint extraction (is it open? did it swipe?) lives in
/// `AirSwipeCore`, where it can be tested without a camera.
final class HandTracker {
    private typealias Joint = VNHumanHandPoseObservation.JointName

    private let request = VNDetectHumanHandPoseRequest()
    // A sequence handler lets Vision reuse state between frames, which steadies
    // the landmarks of a moving hand.
    private let handler = VNSequenceRequestHandler()
    private let mirrorX: Bool

    /// Joints below this confidence are treated as not seen.
    private let minimumConfidence: Float = 0.3

    private let knuckleJoints: [Joint] = [.indexMCP, .middleMCP, .ringMCP, .littleMCP]
    private let fingertipJoints: [Joint] = [.indexTip, .middleTip, .ringTip, .littleTip]

    /// - Parameter mirrorX: Camera frames are not mirrored, so a hand moving to the
    ///   user's right moves left in the image. Mirroring puts x in the user's frame.
    init(mirrorX: Bool = true) {
        self.mirrorX = mirrorX
        request.maximumHandCount = 1
    }

    /// Returns nil when no hand (or no wrist) is visible in this frame.
    func sample(from pixelBuffer: CVPixelBuffer) -> HandSample? {
        do {
            try handler.perform([request], on: pixelBuffer)
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }

        func point(_ joint: Joint) -> CGPoint? {
            guard let recognized = try? observation.recognizedPoint(joint),
                  recognized.confidence >= minimumConfidence else { return nil }
            return recognized.location
        }

        guard let wrist = point(.wrist) else { return nil }

        // Palm center: the wrist plus whichever knuckles were seen. It moves
        // less than a fingertip, so it makes a steadier thing to track.
        let knuckles = knuckleJoints.compactMap(point)
        let palm = [wrist] + knuckles
        let count = CGFloat(palm.count)
        var x = palm.map(\.x).reduce(0, +) / count
        let y = palm.map(\.y).reduce(0, +) / count
        if mirrorX { x = 1 - x }

        // Fingers hidden by curling often come back below the confidence floor;
        // when any joint is missing, the hand is simply "not open".
        let tips = fingertipJoints.compactMap(point)
        let isOpen = OpenPalmClassifier.isOpen(wrist: wrist, knuckles: knuckles, fingertips: tips)

        return HandSample(x: Double(x), y: Double(y), isOpen: isOpen)
    }
}
