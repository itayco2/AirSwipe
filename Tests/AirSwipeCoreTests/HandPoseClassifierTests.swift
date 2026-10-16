import Foundation
import Testing
import AirSwipeCore

@Suite("HandPoseClassifier")
struct HandPoseClassifierTests {
    // Each finger is four joints from the knuckle to the tip, drawn pointing up from
    // a knuckle row at y = 0.30. Values are normalized frame coordinates.
    private let knuckleX = [0.44, 0.48, 0.52, 0.56]

    /// Joints in a straight line: straightness 1.
    private func extended(_ x: Double) -> [CGPoint] {
        [CGPoint(x: x, y: 0.30), CGPoint(x: x, y: 0.36),
         CGPoint(x: x, y: 0.41), CGPoint(x: x, y: 0.45)]
    }

    /// Folded back on itself, as a finger curled into the palm: straightness ~0.2.
    private func curled(_ x: Double) -> [CGPoint] {
        [CGPoint(x: x, y: 0.30), CGPoint(x: x, y: 0.35),
         CGPoint(x: x, y: 0.37), CGPoint(x: x, y: 0.33)]
    }

    /// Bent partway, with straightness 0.90: between "extended" and "curled".
    private func halfBent(_ x: Double) -> [CGPoint] {
        [CGPoint(x: x, y: 0.30), CGPoint(x: x, y: 0.36),
         CGPoint(x: x, y: 0.40), CGPoint(x: x + 0.0266, y: 0.4139)]
    }

    /// Build a hand where `states[i]` is "e" (extended), "c" (curled) or "h" (half).
    private func hand(_ states: String) -> [[CGPoint]] {
        zip(states, knuckleX).map { state, x in
            switch state {
            case "e": return extended(x)
            case "c": return curled(x)
            default: return halfBent(x)
            }
        }
    }

    private func pose(_ states: String) -> HandPose {
        HandPoseClassifier.classify(fingers: hand(states))
    }

    @Test("a straight finger is straightness 1 and a curled one is far lower")
    func straightnessOfAChain() throws {
        let straight = try #require(HandPoseClassifier.straightness(of: extended(0.5)))
        let folded = try #require(HandPoseClassifier.straightness(of: curled(0.5)))
        #expect(abs(straight - 1.0) < 0.001)
        #expect(folded < 0.4)
        #expect(HandPoseClassifier.straightness(of: []) == nil)
    }

    @Test("four extended fingers are an open palm")
    func openPalm() {
        #expect(pose("eeee") == .openPalm)
    }

    @Test("four curled fingers are a fist")
    func fist() {
        #expect(pose("cccc") == .fist)
    }

    @Test("only the index finger extended is one finger")
    func oneFinger() {
        #expect(pose("eccc") == .oneFinger)
    }

    @Test("index and middle extended is two fingers")
    func twoFingers() {
        #expect(pose("eecc") == .twoFingers)
    }

    @Test("three fingers is none of the poses, but two fingers still is")
    func threeFingersIsOther() {
        #expect(pose("eeec") == .other)
        #expect(pose("eecc") == .twoFingers)
    }

    // Field evidence: of 41 unclear readings in one real run, 13 were exactly this,
    // a pointing hand whose little finger read as extended. The little finger is
    // short and often left sticking out, so it must not decide between poses.
    @Test("a little finger that sticks out does not stop one finger being one finger")
    func littleFingerDoesNotDecideOneFinger() {
        #expect(pose("ecce") == .oneFinger)
        #expect(pose("ecch") == .oneFinger)
        #expect(pose("eccc") == .oneFinger)
    }

    @Test("nor does it stop two fingers being two fingers")
    func littleFingerDoesNotDecideTwoFingers() {
        #expect(pose("eece") == .twoFingers)
        #expect(pose("eech") == .twoFingers)
        #expect(pose("eecc") == .twoFingers)
    }

    @Test("the ring finger still matters, and a lone little finger is no pose")
    func ringFingerStillDecides() {
        #expect(pose("ecec") == .other)
        #expect(pose("eeec") == .other)
        #expect(pose("ccce") == .other)
        #expect(pose("cccc") == .fist)
        #expect(pose("eeee") == .openPalm)
    }

    @Test("only the ring finger up is not one finger")
    func ringFingerAloneIsOther() {
        #expect(pose("ccec") == .other)
        #expect(pose("eccc") == .oneFinger)
    }

    @Test("a half-bent finger is undecided, so the hand is not a pose")
    func halfBentFingerIsOther() {
        #expect(pose("hecc") == .other)
        #expect(pose("eecc") == .twoFingers)
    }

    @Test("a finger with joints missing is never a pose, but a complete hand is")
    func missingJointsAreOther() {
        var incomplete = hand("eeee")
        incomplete[2] = []
        #expect(HandPoseClassifier.classify(fingers: incomplete) == .other)
        #expect(HandPoseClassifier.classify(fingers: Array(hand("eeee").dropLast())) == .other)
        #expect(pose("eeee") == .openPalm)
    }

    // The reason this classifier exists: the old one compared fingertips with the
    // wrist, which is out of view when the hand is low in the frame.
    @Test("the pose does not depend on size, so a small or distant hand reads the same")
    func scaleDoesNotMatter() {
        let small = hand("eecc").map { finger in
            finger.map { CGPoint(x: $0.x * 0.3, y: $0.y * 0.3) }
        }
        #expect(HandPoseClassifier.classify(fingers: small) == .twoFingers)
    }

    @Test("the pose does not depend on orientation, so a rotated hand reads the same")
    func rotationDoesNotMatter() {
        let sideways = hand("eecc").map { finger in
            finger.map { CGPoint(x: $0.y, y: -$0.x) }
        }
        #expect(HandPoseClassifier.classify(fingers: sideways) == .twoFingers)
    }
}
