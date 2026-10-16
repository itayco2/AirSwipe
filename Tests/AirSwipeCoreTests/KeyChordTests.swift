import Testing
import AirSwipeCore

@Suite("KeyChord")
struct KeyChordTests {
    @Test("meta+k is the Option key plus K")
    func metaK() {
        #expect(KeyChord.parse("meta+k") == KeyChord(keyCode: 0x28, option: true))
    }

    @Test("meta, opt, option and alt all mean the Option key")
    func optionSpellings() {
        let expected = KeyChord(keyCode: 0x28, option: true)
        for spelling in ["meta+k", "opt+k", "option+k", "alt+k"] {
            #expect(KeyChord.parse(spelling) == expected, "\(spelling)")
        }
    }

    @Test("several modifiers can be combined")
    func severalModifiers() {
        #expect(KeyChord.parse("ctrl+shift+v")
                == KeyChord(keyCode: 0x09, control: true, shift: true))
        #expect(KeyChord.parse("cmd+opt+k")
                == KeyChord(keyCode: 0x28, option: true, command: true))
    }

    @Test("the default voice chord ctrl+opt+d is Control and Option plus D")
    func defaultVoiceChord() {
        #expect(KeyChord.parse("ctrl+opt+d")
                == KeyChord(keyCode: 0x02, control: true, option: true))
    }

    @Test("case and spaces do not matter")
    func caseAndSpaces() {
        #expect(KeyChord.parse(" Ctrl + K ") == KeyChord(keyCode: 0x28, control: true))
    }

    @Test("a key on its own is a chord with no modifiers")
    func bareKeys() {
        #expect(KeyChord.parse("f13") == KeyChord(keyCode: 0x69))
        #expect(KeyChord.parse("space") == KeyChord(keyCode: 0x31))
        #expect(KeyChord.parse("ctrl+\\") == KeyChord(keyCode: 0x2A, control: true))
        #expect(KeyChord.parse("ctrl+backslash") == KeyChord(keyCode: 0x2A, control: true))
    }

    @Test("function keys f1 to f20 are known")
    func functionKeys() {
        for number in 1...20 {
            #expect(KeyChord.parse("f\(number)") != nil, "f\(number)")
        }
    }

    @Test("letters and digits are known")
    func lettersAndDigits() {
        for key in "abcdefghijklmnopqrstuvwxyz0123456789" {
            #expect(KeyChord.parse(String(key)) != nil, "\(key)")
        }
    }

    @Test("things that are not a chord are rejected")
    func invalid() {
        for text in ["", "meta+", "+k", "meta", "ctrl+shift", "k+v", "meta+kk", "hello", "f21"] {
            #expect(KeyChord.parse(text) == nil, "'\(text)'")
        }
    }
}
