import Foundation

/// A keyboard shortcut written like `meta+k` or `ctrl+shift+v`: any modifiers plus
/// exactly one key. It is plain data, so the live sink can turn it into a key press and
/// tests can check parsing with no keyboard.
public struct KeyChord: Equatable {
    public var keyCode: UInt16
    public var control: Bool
    public var option: Bool
    public var command: Bool
    public var shift: Bool

    public init(keyCode: UInt16, control: Bool = false, option: Bool = false,
                command: Bool = false, shift: Bool = false) {
        self.keyCode = keyCode
        self.control = control
        self.option = option
        self.command = command
        self.shift = shift
    }

    /// macOS virtual key codes on an ANSI keyboard (kVK_ANSI_* and kVK_F*), spelled out
    /// so this file needs no Carbon import.
    private static let keyCodes: [String: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06,
        "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E,
        "r": 0x0F, "y": 0x10, "t": 0x11, "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23,
        "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
        "7": 0x1A, "8": 0x1C, "0": 0x1D,
        "space": 0x31, "\\": 0x2A, "backslash": 0x2A,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61,
        "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "f13": 0x69, "f14": 0x6B, "f15": 0x71, "f16": 0x6A, "f17": 0x40, "f18": 0x4F,
        "f19": 0x50, "f20": 0x5A,
    ]

    /// Reads text such as `meta+k`. `meta`, `opt`, `option` and `alt` all mean the Option
    /// key, which terminals send as Meta. Returns nil unless there is exactly one known
    /// key.
    public static func parse(_ text: String) -> KeyChord? {
        var chord = KeyChord(keyCode: 0)
        var key: UInt16?
        for raw in text.split(separator: "+", omittingEmptySubsequences: false) {
            let part = raw.trimmingCharacters(in: .whitespaces).lowercased()
            switch part {
            case "ctrl", "control": chord.control = true
            case "opt", "option", "alt", "meta": chord.option = true
            case "cmd", "command": chord.command = true
            case "shift": chord.shift = true
            default:
                guard key == nil, let code = keyCodes[part] else { return nil }
                key = code
            }
        }
        guard let key else { return nil }
        chord.keyCode = key
        return chord
    }
}
