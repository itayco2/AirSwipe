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

    // MARK: - Thumbs up
    //
    // A thumbs up is a fist with the thumb straight and pointing up. Without telling the
    // two apart it would read as a fist, and a held fist stops AirSwipe.

    private let thumbBase = CGPoint(x: 0.40, y: 0.28)

    /// A straight thumb, joints 0.04 apart, pointing `degrees` away from straight up
    /// (positive leans toward the right of the picture).
    private func straightThumb(degrees: Double) -> [CGPoint] {
        let angle = degrees * .pi / 180
        return (0...3).map { joint in
            let length = 0.04 * Double(joint)
            return CGPoint(x: thumbBase.x + length * sin(angle), y: thumbBase.y + length * cos(angle))
        }
    }

    /// A thumb folded across the palm: its joints double back on themselves.
    private let foldedThumb = [CGPoint(x: 0.40, y: 0.28), CGPoint(x: 0.44, y: 0.31),
                               CGPoint(x: 0.46, y: 0.28), CGPoint(x: 0.43, y: 0.27)]

    /// A thumb bent partway, straightness about 0.81.
    private let bentThumb = [CGPoint(x: 0.40, y: 0.28), CGPoint(x: 0.40, y: 0.33),
                             CGPoint(x: 0.43, y: 0.37), CGPoint(x: 0.47, y: 0.37)]

    private func pose(_ states: String, thumb: [CGPoint]) -> HandPose {
        HandPoseClassifier.classify(fingers: hand(states), thumb: thumb)
    }

    @Test("a fist with the thumb straight and up is a thumbs up")
    func thumbsUp() {
        #expect(pose("cccc", thumb: straightThumb(degrees: 0)) == .thumbsUp)
    }

    @Test("a thumb leaning up to about 30 degrees still counts, but not much further")
    func leaningThumbsUp() {
        #expect(pose("cccc", thumb: straightThumb(degrees: 30)) == .thumbsUp)
        #expect(pose("cccc", thumb: straightThumb(degrees: -30)) == .thumbsUp)
        #expect(pose("cccc", thumb: straightThumb(degrees: 45)) == .fist)
    }

    // Field evidence (dry run, 2026-10-16): the user's relaxed fist left the thumb loosely
    // pointing up (thumb straightness 0.90 to 0.95, up 0.89 to 0.96), so it read as a thumbs
    // up for half a second. A fist is how you stop; a thumbs up sends. What told them apart
    // was the fingers: tightly curled (straightness 0.04 to 0.4) in a real thumbs up,
    // looser (0.5 to 0.77) in the relaxed fist.
    private func looselyCurled(_ x: Double) -> [CGPoint] {
        [CGPoint(x: x, y: 0.30), CGPoint(x: x, y: 0.35),
         CGPoint(x: x + 0.02, y: 0.38), CGPoint(x: x + 0.05, y: 0.36)]
    }

    @Test("a relaxed fist with the thumb loosely up is a fist, not a thumbs up")
    func relaxedFistIsAFist() {
        let loose = knuckleX.map(looselyCurled)
        #expect(HandPoseClassifier.classify(fingers: loose, thumb: straightThumb(degrees: 0)) == .fist)
    }

    @Test("a thumb that is nearly but not quite straight is a fist")
    func almostStraightThumb() {
        let almost = [CGPoint(x: 0.40, y: 0.28), CGPoint(x: 0.40, y: 0.32),
                      CGPoint(x: 0.42, y: 0.355), CGPoint(x: 0.45, y: 0.38)]
        #expect(pose("cccc", thumb: almost) == .fist)
    }

    @Test("a straight thumb pointing sideways or down is still just a fist")
    func thumbNotUpIsAFist() {
        #expect(pose("cccc", thumb: straightThumb(degrees: 60)) == .fist)
        #expect(pose("cccc", thumb: straightThumb(degrees: 90)) == .fist)
        #expect(pose("cccc", thumb: straightThumb(degrees: 180)) == .fist)
    }

    @Test("a folded, bent or missing thumb is a fist, never a thumbs up")
    func thumbNotStraightIsAFist() {
        #expect(pose("cccc", thumb: foldedThumb) == .fist)
        #expect(pose("cccc", thumb: bentThumb) == .fist)
        #expect(pose("cccc", thumb: []) == .fist)
    }

    @Test("a fist read without any thumb information is a fist, as before")
    func fistWithoutThumbArgument() {
        #expect(HandPoseClassifier.classify(fingers: hand("cccc")) == .fist)
    }

    @Test("the thumb only matters when all four fingers are curled")
    func thumbIgnoredOtherwise() {
        let up = straightThumb(degrees: 0)
        #expect(pose("eccc", thumb: up) == .oneFinger)
        #expect(pose("eecc", thumb: up) == .twoFingers)
        #expect(pose("eeee", thumb: up) == .openPalm)
        #expect(pose("ccce", thumb: up) == .other)
    }
}
