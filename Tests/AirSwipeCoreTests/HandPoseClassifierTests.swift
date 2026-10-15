import Foundation
import Testing
import AirSwipeCore

@Suite("HandPoseClassifier")
struct HandPoseClassifierTests {
    // Normalized coordinates, wrist at the bottom, fingers pointing up.
    private let wrist = CGPoint(x: 0.50, y: 0.20)
    private let knuckles = [
        CGPoint(x: 0.44, y: 0.30), CGPoint(x: 0.48, y: 0.31),
        CGPoint(x: 0.52, y: 0.31), CGPoint(x: 0.56, y: 0.30),
    ]
    private let extendedTips = [
        CGPoint(x: 0.40, y: 0.42), CGPoint(x: 0.47, y: 0.45),
        CGPoint(x: 0.53, y: 0.45), CGPoint(x: 0.60, y: 0.42),
    ]
    private let curledTips = [
        CGPoint(x: 0.45, y: 0.27), CGPoint(x: 0.48, y: 0.28),
        CGPoint(x: 0.52, y: 0.28), CGPoint(x: 0.55, y: 0.27),
    ]
    // Index fingertip a quarter farther than its knuckle: neither extended nor curled.
    private let halfwayIndexTip = CGPoint(x: 0.425, y: 0.325)

    /// Build a hand where `extended[i]` says whether finger i is extended.
    private func tips(extended: [Bool]) -> [CGPoint] {
        zip(extended, zip(extendedTips, curledTips)).map { isExtended, pair in
            isExtended ? pair.0 : pair.1
        }
    }

    private func pose(of tips: [CGPoint]) -> HandPose {
        HandPoseClassifier.classify(wrist: wrist, knuckles: knuckles, fingertips: tips)
    }

    @Test("four extended fingers are an open palm")
    func openPalm() {
        #expect(pose(of: tips(extended: [true, true, true, true])) == .openPalm)
    }

    @Test("four curled fingers are a fist")
    func fist() {
        #expect(pose(of: tips(extended: [false, false, false, false])) == .fist)
    }

    @Test("only the index finger extended is one finger")
    func oneFinger() {
        #expect(pose(of: tips(extended: [true, false, false, false])) == .oneFinger)
    }

    @Test("index and middle extended is two fingers")
    func twoFingers() {
        #expect(pose(of: tips(extended: [true, true, false, false])) == .twoFingers)
    }

    @Test("three fingers is none of the poses, but two fingers still is")
    func threeFingersIsOther() {
        #expect(pose(of: tips(extended: [true, true, true, false])) == .other)
        #expect(pose(of: tips(extended: [true, true, false, false])) == .twoFingers)
    }

    @Test("only the ring finger up is not one finger")
    func ringFingerAloneIsOther() {
        #expect(pose(of: tips(extended: [false, false, true, false])) == .other)
        #expect(pose(of: tips(extended: [true, false, false, false])) == .oneFinger)
    }

    @Test("a half-curled finger is undecided, so the hand is not a pose")
    func halfCurledFingerIsOther() {
        var hand = tips(extended: [true, true, false, false])
        hand[0] = halfwayIndexTip
        #expect(pose(of: hand) == .other)
        #expect(pose(of: tips(extended: [true, true, false, false])) == .twoFingers)
    }

    @Test("missing joints are never a pose, but a complete hand is")
    func missingJointsAreOther() {
        #expect(HandPoseClassifier.classify(
            wrist: wrist, knuckles: Array(knuckles.dropLast()),
            fingertips: Array(extendedTips.dropLast())) == .other)
        #expect(pose(of: tips(extended: [true, true, true, true])) == .openPalm)
    }
}
