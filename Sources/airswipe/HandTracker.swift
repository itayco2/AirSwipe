import AirSwipeCore
import CoreGraphics
import Foundation
import Vision

/// Finds one hand in a camera frame and reduces it to a `HandSample`.
///
/// Everything beyond joint extraction (which pose is it? did it swipe?) lives in
/// `AirSwipeCore`, where it can be tested without a camera.
///
/// The wrist is deliberately not used. Held low over a keyboard, a hand has its
/// wrist below the bottom edge of the frame, and anything measured from it turns
/// to noise. The knuckles and fingers stay in view.
final class HandTracker {
    private typealias Joint = VNHumanHandPoseObservation.JointName

    private let request = VNDetectHumanHandPoseRequest()
    // A sequence handler lets Vision reuse state between frames, which steadies
    // the landmarks of a moving hand.
    private let handler = VNSequenceRequestHandler()
    private let mirrorX: Bool
    private let collectDiagnostics: Bool

    /// Joints below this confidence are treated as not seen.
    private let minimumConfidence: Float = 0.3

    // Index to little finger, each joint from the knuckle out to the tip.
    private let fingerJoints: [[Joint]] = [
        [.indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.littleMCP, .littlePIP, .littleDIP, .littleTip],
    ]

    /// The thumb, from its base out to the tip. Only used to tell a thumbs up from a fist.
    private let thumbJoints: [Joint] = [.thumbCMC, .thumbMP, .thumbIP, .thumbTip]

    /// One line describing the latest frame: whether a hand was found, how
    /// straight each finger is, which pose that makes, and where the knuckles are.
    /// Only filled in when diagnostics are on.
    private(set) var diagnostics = ""

    /// - Parameters:
    ///   - mirrorX: Camera frames are not mirrored, so a hand moving to the user's
    ///     right moves left in the image. Mirroring puts x in the user's frame.
    ///   - collectDiagnostics: Record what was seen each frame in `diagnostics`.
    init(mirrorX: Bool = true, collectDiagnostics: Bool = false) {
        self.mirrorX = mirrorX
        self.collectDiagnostics = collectDiagnostics
        request.maximumHandCount = 1
    }

    /// Returns nil when no hand is visible in this frame.
    func sample(from pixelBuffer: CVPixelBuffer) -> HandSample? {
        do {
            try handler.perform([request], on: pixelBuffer)
        } catch {
            if collectDiagnostics { diagnostics = "hand=NO (vision error)" }
            return nil
        }
        guard let observation = request.results?.first else {
            if collectDiagnostics { diagnostics = "hand=NO" }
            return nil
        }

        func point(_ joint: Joint) -> CGPoint? {
            guard let recognized = try? observation.recognizedPoint(joint),
                  recognized.confidence >= minimumConfidence else { return nil }
            return recognized.location
        }

        // Position: the centroid of the knuckles. It stays in frame when the hand
        // is low, and it moves less than a fingertip or a wrist.
        let knuckles = fingerJoints.compactMap { point($0[0]) }
        guard knuckles.count >= 3 else {
            if collectDiagnostics { diagnostics = "hand=WEAK knuckles=\(knuckles.count)" }
            return nil
        }
        let count = CGFloat(knuckles.count)
        var x = knuckles.map(\.x).reduce(0, +) / count
        let y = knuckles.map(\.y).reduce(0, +) / count
        if mirrorX { x = 1 - x }

        // Pose: how straight each finger is. A finger with any joint unseen is
        // passed empty, and the classifier then reports `.other`.
        let fingers: [[CGPoint]] = fingerJoints.map { joints in
            let chain = joints.compactMap(point)
            return chain.count == joints.count ? chain : []
        }
        let thumbChain = thumbJoints.compactMap(point)
        let thumb = thumbChain.count == thumbJoints.count ? thumbChain : []
        let pose = HandPoseClassifier.classify(fingers: fingers, thumb: thumb)

        if collectDiagnostics {
            diagnostics = "hand=yes " + describe(observation, fingers: fingers, thumb: thumb,
                                                 pose: pose, x: x, y: y)
        }
        return HandSample(x: Double(x), y: Double(y), pose: pose)
    }

    // MARK: - Diagnostics

    private func describe(_ observation: VNHumanHandPoseObservation,
                          fingers: [[CGPoint]], thumb: [CGPoint],
                          pose: HandPose, x: CGFloat, y: CGFloat) -> String {
        func format(_ value: Double) -> String { String(format: "%.2f", value) }

        let straightness = fingers.map { chain -> String in
            HandPoseClassifier.straightness(of: chain).map(format) ?? "--"
        }
        let wrist = (try? observation.recognizedPoint(.wrist)).map { format(Double($0.confidence)) } ?? "--"
        let confidences = fingerJoints.map { joints -> String in
            (try? observation.recognizedPoint(joints[3])).map { format(Double($0.confidence)) } ?? "--"
        }

        // The thumb: how straight it is, then how far it points up (1 straight up, 0
        // sideways, -1 down). A thumbs up needs both high: see HandPoseClassifier.
        var thumbText = "--"
        if let base = thumb.first, let tip = thumb.last,
           let straight = HandPoseClassifier.straightness(of: thumb) {
            let length = hypot(Double(tip.x - base.x), Double(tip.y - base.y))
            let up = length > 0 ? Double(tip.y - base.y) / length : 0
            thumbText = "\(format(straight))/\(format(up))"
        }

        var pinchText = "--"
        if let pinch = pinchReading(observation) {
            pinchText = "\(format(pinch.ratio))/\(format(pinch.confidence))"
        }

        return "pose=\(pose) str=\(straightness.joined(separator: "/")) thumb=\(thumbText) "
            + "pinch=\(pinchText) "
            + "tipConf=\(confidences.joined(separator: "/")) wrist=\(wrist) "
            + "x=\(format(Double(x))) y=\(format(Double(y)))"
    }

    /// How close the thumb tip is to the index tip, as a share of the width of the
    /// knuckles (index to little finger), so it does not depend on how far the hand is
    /// from the camera. Small when the two touch. `confidence` is the weaker of the two
    /// tips'. Heights are scaled by the frame's aspect ratio so the distance is round.
    private func pinchReading(_ observation: VNHumanHandPoseObservation) -> (ratio: Double, confidence: Double)? {
        func joint(_ name: Joint) -> (point: CGPoint, confidence: Double)? {
            guard let recognized = try? observation.recognizedPoint(name),
                  recognized.confidence >= minimumConfidence else { return nil }
            return (recognized.location, Double(recognized.confidence))
        }
        guard let thumbTip = joint(.thumbTip), let indexTip = joint(.indexTip),
              let indexKnuckle = joint(.indexMCP), let littleKnuckle = joint(.littleMCP) else {
            return nil
        }
        func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
            hypot(Double(a.x - b.x), Double(a.y - b.y) * 0.75)
        }
        let width = distance(indexKnuckle.point, littleKnuckle.point)
        guard width > 0 else { return nil }
        return (distance(thumbTip.point, indexTip.point) / width,
                min(thumbTip.confidence, indexTip.confidence))
    }
}
