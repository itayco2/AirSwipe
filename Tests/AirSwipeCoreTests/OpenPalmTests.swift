import Foundation
import Testing
import AirSwipeCore

@Suite("OpenPalmClassifier")
struct OpenPalmTests {
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

    @Test("four extended fingers are an open palm")
    func extendedIsOpen() {
        #expect(OpenPalmClassifier.isOpen(wrist: wrist, knuckles: knuckles, fingertips: extendedTips))
    }

    @Test("a fist is not an open palm, but the same hand opened is")
    func fistIsNotOpen() {
        #expect(!OpenPalmClassifier.isOpen(wrist: wrist, knuckles: knuckles, fingertips: curledTips))
        #expect(OpenPalmClassifier.isOpen(wrist: wrist, knuckles: knuckles, fingertips: extendedTips))
    }

    @Test("one curled finger is enough to not count as open")
    func oneCurledFingerIsNotOpen() {
        var tips = extendedTips
        tips[2] = curledTips[2]
        #expect(!OpenPalmClassifier.isOpen(wrist: wrist, knuckles: knuckles, fingertips: tips))
        #expect(OpenPalmClassifier.isOpen(wrist: wrist, knuckles: knuckles, fingertips: extendedTips))
    }

    @Test("missing joints are never an open palm, but a complete hand is")
    func missingJointsAreNotOpen() {
        #expect(!OpenPalmClassifier.isOpen(
            wrist: wrist, knuckles: Array(knuckles.dropLast()),
            fingertips: Array(extendedTips.dropLast())))
        #expect(OpenPalmClassifier.isOpen(wrist: wrist, knuckles: knuckles, fingertips: extendedTips))
    }
}
