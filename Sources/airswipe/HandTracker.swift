import AirSwipeCore
import CoreGraphics
import Foundation
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
    private let collectDiagnostics: Bool

    /// Joints below this confidence are treated as not seen.
    private let minimumConfidence: Float = 0.3

    private let knuckleJoints: [Joint] = [.indexMCP, .middleMCP, .ringMCP, .littleMCP]
    private let fingertipJoints: [Joint] = [.indexTip, .middleTip, .ringTip, .littleTip]

    /// One line describing the latest frame: whether a hand was found, how
    /// confident each fingertip was, how far each finger reaches past its
    /// knuckle, and where the palm is. Only filled in when diagnostics are on.
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

    /// Returns nil when no hand (or no wrist) is visible in this frame.
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

        guard let wrist = point(.wrist) else {
            if collectDiagnostics {
                diagnostics = "hand=WEAK " + describe(observation, isOpen: nil, x: nil, y: nil)
            }
            return nil
        }

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

        if collectDiagnostics {
            diagnostics = "hand=yes " + describe(observation, isOpen: isOpen, x: x, y: y)
        }
        return HandSample(x: Double(x), y: Double(y), isOpen: isOpen)
    }

    // MARK: - Diagnostics

    /// Raw joint data straight from Vision, ignoring the confidence floor, so we
    /// can see *why* the hand was or was not classified as open.
    private func describe(_ observation: VNHumanHandPoseObservation,
                          isOpen: Bool?, x: CGFloat?, y: CGFloat?) -> String {
        func raw(_ joint: Joint) -> VNRecognizedPoint? {
            try? observation.recognizedPoint(joint)
        }
        func format(_ value: Double) -> String { String(format: "%.2f", value) }

        let wrist = raw(.wrist)
        var confidences: [String] = []
        var ratios: [String] = []

        for (knuckleJoint, tipJoint) in zip(knuckleJoints, fingertipJoints) {
            let tip = raw(tipJoint)
            confidences.append(tip.map { format(Double($0.confidence)) } ?? "--")

            if let wrist, let knuckle = raw(knuckleJoint), let tip {
                let base = hypot(Double(knuckle.location.x - wrist.location.x),
                                 Double(knuckle.location.y - wrist.location.y))
                let reach = hypot(Double(tip.location.x - wrist.location.x),
                                  Double(tip.location.y - wrist.location.y))
                ratios.append(base > 0 ? format(reach / base) : "--")
            } else {
                ratios.append("--")
            }
        }

        let openText = isOpen.map { $0 ? "Y" : "N" } ?? "?"
        let position = (x != nil && y != nil)
            ? "x=\(format(Double(x ?? 0))) y=\(format(Double(y ?? 0)))"
            : "x=-- y=--"
        let wristText = wrist.map { format(Double($0.confidence)) } ?? "--"

        return "wrist=\(wristText) open=\(openText) "
            + "ratio=\(ratios.joined(separator: "/")) "
            + "tipConf=\(confidences.joined(separator: "/")) \(position)"
    }
}
