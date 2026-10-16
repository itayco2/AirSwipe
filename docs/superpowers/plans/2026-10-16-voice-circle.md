# Voice Circle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An open-palm circle in the air presses Claude Code's own push-to-talk key, so a developer can start and stop voice dictation without touching the keyboard.

**Architecture:** A pure, clock-free `CircleDetector` in `AirSwipeCore` recognizes the circle, the engine emits `GestureEvent.circle` in palm mode, and the mapper turns it into `Action.toggleVoice`. The live sink posts one key chord (parsed by a pure `KeyChord`), so AirSwipe contains no audio code. A throwaway spike runs first to prove a synthetic key press can start Claude Code recording at all.

**Tech Stack:** Swift 6.1 (language mode 5), SwiftPM, CoreGraphics `CGEvent`, AppKit `NSStatusItem`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-16-voice-circle-design.md`

## Global Constraints

- macOS 13+, Command Line Tools only (no Xcode.app); tests use Swift Testing (`import Testing`), not XCTest.
- `AirSwipeCore` must not import AVFoundation, Vision, AppKit or CoreGraphics. `KeyChord` stays a plain value type; the `CGEventFlags` conversion lives in `Sources/airswipe/Sinks.swift`.
- Default run mode is dry-run; only `--live` may post synthetic events. Voice is off unless `--voice` (or `--voice-key`) is given.
- Circle: open palm only, only while armed, either direction. Starting values: window 1.5 s, turn at least 5.5 rad (about 315°), extent at least 0.10 across and down, roundness 0.5, cooldown 1 s, aspect ratio 0.75.
- One circle sends one key press (down, then up). The recording state is assumed to flip on each circle and resets when AirSwipe disarms.
- Unclear pose readings (`.other`, `.fist`) must not end palm mode, for up to `strokePoseHold`.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/AirSwipeCore/KeyChord.swift` (new) | Parse `"meta+k"` into a key code plus modifiers. Pure. |
| `Sources/AirSwipeCore/CircleDetector.swift` (new) | Decide from timestamped positions whether a circle was drawn. Pure. |
| `Sources/AirSwipeCore/Types.swift` | `GestureEvent.circle` and the circle config fields. |
| `Sources/AirSwipeCore/GestureEngine.swift` | Feed palm positions to the detector; keep palm mode through unclear poses. |
| `Sources/AirSwipeCore/ActionMapper.swift` | `Action.toggleVoice`; `.circle` maps to it. |
| `Sources/airswipe/Sinks.swift` | Post the chord (live) or print it (dry run). |
| `Sources/airswipe/StatusItem.swift` | A 🎙 mark while recording is assumed. |
| `Sources/airswipe/main.swift` | `--voice`, `--voice-key`, wiring, help text. |
| `Tests/AirSwipeCoreTests/KeyChordTests.swift` (new) | Chord parsing. |
| `Tests/AirSwipeCoreTests/CircleDetectorTests.swift` (new) | Circle shapes, sizes, speeds, rejects. |
| `Tests/AirSwipeCoreTests/GestureEngineTests.swift` | Engine-level circle and palm-mode tests. |
| `Tests/AirSwipeCoreTests/ActionMapperTests.swift` | `.circle` to `.toggleVoice`. |
| `docs/superpowers/spike-voice-key.md` (new) | The spike's recorded result. |

---

### Task 1: Spike — can a synthetic key press start Claude Code recording?

This task needs the user at the keyboard. **If no chord works, stop here: do not start Task 2. Tell the user and revisit the spec.**

**Files:**
- Create (outside the repo, in the session scratchpad directory): `spike-key.swift`
- Create (user config, only with the user's OK): `~/.claude/keybindings.json` (it does not exist yet)
- Create: `docs/superpowers/spike-voice-key.md`

**Interfaces:**
- Produces: a recorded decision, the chord that works, used as `defaultVoiceChord` in Task 5.

- [ ] **Step 1: Write the throwaway script**

```swift
// Throwaway: posts one key chord after a delay, to test whether Claude Code's voice
// key can be pressed by a synthetic event.
// Usage: swift spike-key.swift <chord> [delaySeconds]    e.g.  swift spike-key.swift meta+k 5
import ApplicationServices
import CoreGraphics
import Foundation

let codes: [String: CGKeyCode] = [
    "k": 0x28, "v": 0x09, "space": 0x31, "\\": 0x2A,
    "f13": 0x69, "f14": 0x6B, "f15": 0x71,
]

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: swift spike-key.swift <chord> [delaySeconds]")
    exit(2)
}
let delay = args.count >= 3 ? (Double(args[2]) ?? 5) : 5

var flags: CGEventFlags = []
var keyName = ""
for part in args[1].lowercased().split(separator: "+").map(String.init) {
    switch part {
    case "ctrl", "control": flags.insert(.maskControl)
    case "opt", "option", "alt", "meta": flags.insert(.maskAlternate)
    case "cmd", "command": flags.insert(.maskCommand)
    case "shift": flags.insert(.maskShift)
    default: keyName = part
    }
}
guard let code = codes[keyName] else {
    print("unknown key '\(keyName)'")
    exit(2)
}

if !AXIsProcessTrusted() {
    print("warning: this terminal app may not post events. Allow it in System Settings > Privacy & Security > Accessibility.")
}
print("pressing \(args[1]) in \(Int(delay)) s: click the window running Claude Code now")
Thread.sleep(forTimeInterval: delay)

let source = CGEventSource(stateID: .hidSystemState)
for isDown in [true, false] {
    let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown)
    event?.flags = flags
    event?.post(tap: .cghidEventTap)
}
print("sent \(args[1])")
```

- [ ] **Step 2: Get the user's OK, then create the keybinding**

Show the user this exact file and ask before writing it, because it is their Claude Code config:

```json
{ "bindings": [ { "context": "Chat", "bindings": { "meta+k": "voice:pushToTalk" } } ] }
```

Create `~/.claude/keybindings.json` with it. (For later candidates, only the chord string on the left changes.)

- [ ] **Step 3: The user prepares two Terminal.app windows**

1. Terminal.app > Settings > Profiles > Keyboard: tick **Use Option as Meta key** (needed for `meta+k`).
2. Window A: run `claude`, then type `/voice tap`. Expect the microphone check to pass and the mode to read "tap". Leave the cursor in the prompt box.
3. Window B: stays at a shell prompt.

- [ ] **Step 4: Press the chord**

In window B: `swift <scratchpad>/spike-key.swift meta+k 5`, then within 5 seconds click window A's prompt box.
Expected: Claude Code shows that it is recording. Say a short sentence. Run the same command again (second press).
Expected: recording stops and the transcript appears in the prompt box.

- [ ] **Step 5: If it fails, try the other candidates, one at a time**

For each, edit the left side of the binding in `~/.claude/keybindings.json`, restart `claude` and `/voice tap`, then run the script with the matching chord: `ctrl+\`, then `f13`. If Claude Code rejects a chord name in its keybindings, note the message and skip that candidate.

- [ ] **Step 6: Record the result and commit**

Create `docs/superpowers/spike-voice-key.md`, fill in one row per chord actually tried, and state the decision:

```markdown
# Voice key spike: result

- Date:
- Terminal: Terminal.app, "Use Option as Meta key" on or off
- Claude Code version (`claude --version`):

| Chord | Binding accepted by Claude Code | First press started recording | Second press stopped and sent | Notes |
|---|---|---|---|---|

**Decision:** the default chord is `...` (or: no chord works, design to be revisited).
```

```bash
git add docs/superpowers/spike-voice-key.md
git commit -m "docs: record which synthetic key press starts Claude Code recording"
```

If the decision is anything other than `meta+k`, use that chord for `defaultVoiceChord` in Task 5 and in the README and spec examples in Task 6.

---

### Task 2: `KeyChord` parser

**Files:**
- Create: `Sources/AirSwipeCore/KeyChord.swift`
- Test: `Tests/AirSwipeCoreTests/KeyChordTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct KeyChord: Equatable {
      public var keyCode: UInt16
      public var control: Bool
      public var option: Bool
      public var command: Bool
      public var shift: Bool
      public init(keyCode: UInt16, control: Bool = false, option: Bool = false,
                  command: Bool = false, shift: Bool = false)
      public static func parse(_ text: String) -> KeyChord?
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `swift test --filter KeyChordTests`
Expected: FAIL to compile, "cannot find 'KeyChord' in scope".

- [ ] **Step 3: Write the implementation**

```swift
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
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter KeyChordTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AirSwipeCore/KeyChord.swift Tests/AirSwipeCoreTests/KeyChordTests.swift
git commit -m "feat: parse key chords like meta+k for the voice key"
```

---

### Task 3: `CircleDetector`

**Files:**
- Create: `Sources/AirSwipeCore/CircleDetector.swift`
- Modify: `Sources/AirSwipeCore/Types.swift` (add the circle config fields)
- Test: `Tests/AirSwipeCoreTests/CircleDetectorTests.swift`

**Interfaces:**
- Consumes: `GestureConfig` (public struct, `Types.swift`).
- Produces (internal to `AirSwipeCore`, tests use `@testable import`):
  ```swift
  struct CircleDetector {
      init(config: GestureConfig)
      mutating func reset()
      mutating func add(x: Double, y: Double, at time: Double) -> Bool   // true when a circle just completed
  }
  ```
  and these `GestureConfig` fields: `circleEnabled: Bool = false`, `circleWindow: Double = 1.5`, `circleMinTurn: Double = 5.5`, `circleMinSize: Double = 0.10`, `circleMinRoundness: Double = 0.5`, `circleCooldown: Double = 1.0`, `circleAspectRatio: Double = 0.75`.

- [ ] **Step 1: Add the config fields**

In `Sources/AirSwipeCore/Types.swift`, immediately above `public init() {}` in `GestureConfig`, insert:

```swift
    // Circle: an open palm drawing a circle starts and stops voice recording. Off
    // unless `circleEnabled`, so nothing changes for anyone who does not ask for it.
    public var circleEnabled: Bool = false
    /// The circle must be completed within this many seconds.
    public var circleWindow: Double = 1.5
    /// The path must turn through at least this many radians in one direction. 5.5 is
    /// about 315 degrees; a person rarely closes the loop exactly.
    public var circleMinTurn: Double = 5.5
    /// The path must span at least this much across and down, in frame widths, so a hand
    /// at rest and small tremors never count.
    public var circleMinSize: Double = 0.10
    /// The nearest point may be no closer to the centre than this share of the farthest,
    /// so a line, a flat oval or a figure of eight does not count.
    public var circleMinRoundness: Double = 0.5
    /// After a circle, ignore further circles for this long.
    public var circleCooldown: Double = 1.0
    /// Frame height divided by frame width (480 / 640). Heights are scaled by it so a
    /// round motion is round in the maths.
    public var circleAspectRatio: Double = 0.75

```

- [ ] **Step 2: Write the failing tests**

```swift
import Foundation
import Testing
@testable import AirSwipeCore

@Suite("CircleDetector")
struct CircleDetectorTests {
    private typealias Path = [(t: Double, x: Double, y: Double)]
    private let aspect = 0.75

    /// A circle that is round in the picture: frame heights are scaled by `aspect`, so
    /// the y radius is larger in frame units.
    private func circle(radius: Double, seconds: Double, turns: Double = 1.0,
                        clockwise: Bool = false, start: Double = 0) -> Path {
        let steps = Int(seconds * 30)
        let sign = clockwise ? -1.0 : 1.0
        return (0...steps).map { k in
            let angle = sign * turns * 2 * .pi * Double(k) / Double(steps)
            return (start + Double(k) / 30,
                    0.5 + radius * cos(angle),
                    0.5 + radius * sin(angle) / aspect)
        }
    }

    /// The times at which the detector reported a circle.
    private func firings(_ path: Path) -> [Double] {
        var detector = CircleDetector(config: GestureConfig())
        return path.compactMap { detector.add(x: $0.x, y: $0.y, at: $0.t) ? $0.t : nil }
    }

    @Test("a counter-clockwise circle is a circle, once")
    func counterClockwise() {
        #expect(firings(circle(radius: 0.12, seconds: 1.0)).count == 1)
    }

    @Test("a clockwise circle is a circle too")
    func clockwise() {
        #expect(firings(circle(radius: 0.12, seconds: 1.0, clockwise: true)).count == 1)
    }

    @Test("small and large circles both count")
    func sizes() {
        for radius in [0.06, 0.09, 0.15, 0.20] {
            #expect(firings(circle(radius: radius, seconds: 1.0)).count == 1, "radius \(radius)")
        }
    }

    @Test("fast and unhurried circles both count")
    func speeds() {
        for seconds in [0.6, 1.0, 1.4] {
            #expect(firings(circle(radius: 0.12, seconds: seconds)).count == 1, "\(seconds) s")
        }
    }

    @Test("a circle drawn after the hand rested still counts")
    func afterRest() {
        #expect(firings(circle(radius: 0.12, seconds: 1.0, start: 2.0)).count == 1)
    }

    @Test("one circle fires once, even if the hand keeps going round")
    func firesOnce() {
        #expect(firings(circle(radius: 0.12, seconds: 1.3, turns: 1.3)).count == 1)
    }

    @Test("a second circle after the cooldown fires again")
    func firesAgain() {
        let path = circle(radius: 0.12, seconds: 1.0)
            + circle(radius: 0.12, seconds: 1.0, start: 3.0)
        #expect(firings(path).count == 2)
    }

    @Test("a half circle is not a circle")
    func halfCircle() {
        #expect(firings(circle(radius: 0.12, seconds: 0.5, turns: 0.5)).isEmpty)
    }

    @Test("a circle too slow to finish inside the window is not a circle")
    func slowCircle() {
        #expect(firings(circle(radius: 0.12, seconds: 4.0)).isEmpty)
    }

    @Test("a straight back-and-forth wave is not a circle")
    func wave() {
        let path: Path = (0...90).map { k in
            let t = Double(k) / 30
            return (t, 0.5 + 0.2 * sin(2 * .pi * 1.5 * t), 0.5)
        }
        #expect(firings(path).isEmpty)
    }

    @Test("a diagonal wave is not a circle")
    func diagonalWave() {
        let path: Path = (0...90).map { k in
            let t = Double(k) / 30
            let s = 0.15 * sin(2 * .pi * 1.5 * t)
            return (t, 0.5 + s, 0.5 + s / aspect)
        }
        #expect(firings(path).isEmpty)
    }

    @Test("a figure of eight is not a circle")
    func figureOfEight() {
        let path: Path = (0...36).map { k in
            let theta = 2 * Double.pi * Double(k) / 36
            return (Double(k) / 30,
                    0.5 + 0.12 * sin(theta),
                    0.5 + 0.12 * sin(theta) * cos(theta) / aspect)
        }
        #expect(firings(path).isEmpty)
    }

    @Test("a small wobble is not a circle")
    func smallWobble() {
        #expect(firings(circle(radius: 0.02, seconds: 1.0)).isEmpty)
    }

    @Test("a still hand with jitter is not a circle")
    func jitter() {
        let path: Path = (0...120).map { k in
            let t = Double(k) / 30
            return (t, 0.5 + 0.004 * sin(7 * t), 0.5 + 0.004 * cos(11 * t))
        }
        #expect(firings(path).isEmpty)
    }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `swift test --filter CircleDetectorTests`
Expected: FAIL to compile, "cannot find 'CircleDetector' in scope".

- [ ] **Step 4: Write the implementation**

```swift
import Foundation

/// Recognizes a hand drawing a circle in the air.
///
/// Pure and clock-free like the rest of the core: positions arrive with timestamps. A
/// circle is a path that, within `circleWindow`, turns through nearly a full turn in
/// one direction around its own centre, is wide and tall enough to be deliberate, and
/// stays round. A back-and-forth wave turns by about zero and a figure of eight cancels
/// itself, so neither counts.
struct CircleDetector {
    private let config: GestureConfig
    private var points: [(time: Double, x: Double, y: Double)] = []
    private var lastFire = -Double.infinity

    /// Positions closer than this to the last kept one are dropped, so a hand at rest
    /// adds no points and cannot pull the centre of the path off the circle.
    private let minStep = 0.004
    private let minPoints = 8

    init(config: GestureConfig) {
        self.config = config
    }

    mutating func reset() {
        points.removeAll()
    }

    /// Feed one position. Returns true at the moment a circle is completed.
    mutating func add(x: Double, y: Double, at time: Double) -> Bool {
        let scaledY = y * config.circleAspectRatio
        if let last = points.last, hypot(x - last.x, scaledY - last.y) < minStep {
            return false
        }
        points.append((time, x, scaledY))
        points.removeAll { time - $0.time > config.circleWindow }

        guard time - lastFire >= config.circleCooldown,
              points.count >= minPoints,
              isCircle() else { return false }
        points.removeAll()
        lastFire = time
        return true
    }

    private func isCircle() -> Bool {
        let count = Double(points.count)
        let centerX = points.reduce(0) { $0 + $1.x } / count
        let centerY = points.reduce(0) { $0 + $1.y } / count

        // Big enough to be deliberate: wide and tall.
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(),
              maxX - minX >= config.circleMinSize,
              maxY - minY >= config.circleMinSize else { return false }

        // Round: no point strays much nearer the centre than the farthest one.
        let radii = points.map { hypot($0.x - centerX, $0.y - centerY) }
        guard let nearest = radii.min(), let farthest = radii.max(), farthest > 0,
              nearest / farthest >= config.circleMinRoundness else { return false }

        // Turning: add up the signed angle between neighbouring points around the
        // centre. A circle gives about +-2 pi; a wave or a figure of eight cancels out.
        var turn = 0.0
        var travelled = 0.0
        var previous = atan2(points[0].y - centerY, points[0].x - centerX)
        for point in points.dropFirst() {
            let angle = atan2(point.y - centerY, point.x - centerX)
            var delta = angle - previous
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            turn += delta
            travelled += abs(delta)
            previous = angle
        }
        // Mostly one direction: wobble may not make up more than 60% extra travel.
        return abs(turn) >= config.circleMinTurn && travelled <= 1.6 * abs(turn)
    }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `swift test --filter CircleDetectorTests`
Expected: PASS (14 tests).
If a size or speed case fails, print the detector's `turn` and `nearest / farthest` for that path and adjust the starting values in `Types.swift` (the spec marks them as tunable), not the tests' expectations.

- [ ] **Step 6: Commit**

```bash
git add Sources/AirSwipeCore/CircleDetector.swift Sources/AirSwipeCore/Types.swift Tests/AirSwipeCoreTests/CircleDetectorTests.swift
git commit -m "feat: recognize a circle drawn in the air"
```

---

### Task 4: The engine emits `.circle` in palm mode; the mapper turns it into `.toggleVoice`

**Files:**
- Modify: `Sources/AirSwipeCore/Types.swift` (new event case)
- Modify: `Sources/AirSwipeCore/GestureEngine.swift`
- Modify: `Sources/AirSwipeCore/ActionMapper.swift`
- Modify (keep the executable compiling until Task 5): `Sources/airswipe/Sinks.swift`, `Sources/airswipe/main.swift`
- Test: `Tests/AirSwipeCoreTests/GestureEngineTests.swift`, `Tests/AirSwipeCoreTests/ActionMapperTests.swift`

**Interfaces:**
- Consumes: `CircleDetector.add(x:y:at:)`, `CircleDetector.reset()`, the `circle*` config fields (Task 3).
- Produces: `GestureEvent.circle`; `Action.toggleVoice`; `ActionMapper.actions(for: .circle) == [.toggleVoice]`.

- [ ] **Step 1: Write the failing engine tests**

Append to the end of `Tests/AirSwipeCoreTests/GestureEngineTests.swift`:

```swift

// MARK: - Circle

extension Rig {
    /// Draws a circle that is round in the picture, starting at the current position
    /// (the circle's rightmost point). Counter-clockwise unless `clockwise`.
    @discardableResult
    mutating func drawCircle(radius: Double, seconds: Double, turns: Double = 1.0,
                             clockwise: Bool = false, pose override: HandPose? = nil) -> [GestureEvent] {
        let steps = max(1, Int((seconds * fps).rounded()))
        let centerX = x - radius
        let centerY = y
        let sign = clockwise ? -1.0 : 1.0
        var events: [GestureEvent] = []
        for step in 1...steps {
            let angle = sign * turns * 2 * .pi * Double(step) / Double(steps)
            events += move(toX: centerX + radius * cos(angle),
                           toY: centerY + radius * sin(angle) / 0.75,
                           over: seconds / Double(steps), pose: override)
        }
        return events
    }
}

@Suite("Circle")
struct CircleEngineTests {
    private func voiceConfig() -> GestureConfig {
        var config = GestureConfig()
        config.circleEnabled = true
        return config
    }

    @Test("an open-palm circle is a circle, and nothing else")
    func palmCircle() {
        var rig = Rig.armed(config: voiceConfig())
        let events = rig.drawCircle(radius: 0.10, seconds: 1.0)
        #expect(events == [.circle])
    }

    @Test("a clockwise palm circle counts too")
    func palmCircleClockwise() {
        var rig = Rig.armed(config: voiceConfig())
        let events = rig.drawCircle(radius: 0.10, seconds: 1.0, clockwise: true)
        #expect(events == [.circle])
    }

    @Test("a second circle straight away is ignored, one after the cooldown counts")
    func cooldown() {
        var rig = Rig.armed(config: voiceConfig())
        var events = rig.drawCircle(radius: 0.10, seconds: 1.0)
        events += rig.drawCircle(radius: 0.10, seconds: 0.3, turns: 0.3)
        rig.hold(for: 2.0)
        events += rig.drawCircle(radius: 0.10, seconds: 1.0)
        #expect(events == [.circle, .circle])
    }

    @Test("with voice off, a palm circle does nothing")
    func offByDefault() {
        var rig = Rig.armed()
        #expect(rig.drawCircle(radius: 0.10, seconds: 1.0).isEmpty)
    }

    @Test("a circle while not armed does nothing")
    func notArmed() {
        var rig = Rig(config: voiceConfig())
        #expect(rig.drawCircle(radius: 0.10, seconds: 1.0).isEmpty)
    }

    @Test("a half circle does nothing")
    func halfCircle() {
        var rig = Rig.armed(config: voiceConfig())
        #expect(rig.drawCircle(radius: 0.10, seconds: 0.5, turns: 0.5).isEmpty)
    }

    @Test("one finger drawing a circle is not a voice circle")
    func oneFingerCircle() {
        var rig = Rig.swiping(config: voiceConfig())
        let events = rig.drawCircle(radius: 0.10, seconds: 1.0)
        #expect(!events.contains(.circle))
    }

    @Test("two fingers drawing a circle is not a voice circle")
    func twoFingerCircle() {
        var rig = Rig.scrolling(config: voiceConfig())
        let events = rig.drawCircle(radius: 0.10, seconds: 1.0)
        #expect(!events.contains(.circle))
    }

    // The whole stretch (hold plus circle up to the moment it completes) must stay inside
    // `strokePoseHold` (1 s), or palm mode lapses mid-circle on purpose.
    @Test("palm mode survives unclear pose readings, so the circle still counts")
    func unclearPoseKeepsPalmMode() {
        var rig = Rig.armed(config: voiceConfig())
        rig.hold(for: 0.2, pose: .other)
        let events = rig.drawCircle(radius: 0.10, seconds: 0.7, pose: .other)
        #expect(events == [.circle])
    }

    @Test("but a long stretch with no palm reading ends palm mode")
    func longUnclearStretchEndsPalmMode() {
        var rig = Rig.armed(config: voiceConfig())
        rig.hold(for: 1.5, pose: .other)
        let events = rig.drawCircle(radius: 0.10, seconds: 1.0, pose: .other)
        #expect(events.isEmpty)
    }

    @Test("a held fist still stops it, even in palm mode")
    func fistStillDisarms() {
        var rig = Rig.armed(config: voiceConfig())
        let events = rig.hold(for: 0.8, pose: .fist)
        #expect(events.contains(.disarmed))
    }
}
```

- [ ] **Step 2: Write the failing mapper test**

In `Tests/AirSwipeCoreTests/ActionMapperTests.swift`, add inside `struct ActionMapperTests` (before its closing brace):

```swift

    @Test("a circle toggles voice recording")
    func circleTogglesVoice() {
        let mapper = ActionMapper()
        #expect(mapper.actions(for: .circle) == [.toggleVoice])
    }
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `swift test`
Expected: FAIL to compile, "type 'GestureEvent' has no member 'circle'".

- [ ] **Step 4: Add the event and the action**

In `Sources/AirSwipeCore/Types.swift`, inside `public enum GestureEvent`, after the `case scroll(amount: Double)` line, add:

```swift
    /// An open palm drew a circle in the air: toggle voice recording.
    case circle
```

In `Sources/AirSwipeCore/ActionMapper.swift`, inside `public enum Action`, after `case scroll(pixels: Int32)`, add:

```swift
    /// Press the voice key once: starts recording, or stops it if already recording.
    case toggleVoice
```

and in `actions(for:)`, after the `case .flick:` branch (which returns `[]`), add:

```swift
        case .circle:
            return [.toggleVoice]
```

- [ ] **Step 5: Wire the detector and palm-mode stickiness into the engine**

In `Sources/AirSwipeCore/GestureEngine.swift`:

1. Next to the existing `lastSwipePoseTime` property, add:

```swift
    /// The last time an open palm was read, however briefly, for palm mode's hold.
    private var lastPalmPoseTime: TimeInterval = -.infinity
    private var circle: CircleDetector
```

2. In `init(config:)`, set both stored properties:

```swift
    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
        self.circle = CircleDetector(config: config)
    }
```

3. In `processIdle`, in the block that arms (right after `mode = .openPalm`), add `lastPalmPoseTime = time` so a palm that has just armed counts as just seen:

```swift
                mode = .openPalm
                lastPalmPoseTime = time
```

4. Replace the first lines of `updateMode(for:at:)` (everything from `if sample.pose == config.swipePose {` through the closing `}` of the unclear-pose block that ends with `return`) with:

```swift
        if sample.pose == config.swipePose {
            lastSwipePoseTime = time
        }
        if sample.pose == .openPalm {
            lastPalmPoseTime = time
        }
        let isUnclear = sample.pose == .other || sample.pose == .fist
        if isUnclear, mode == config.swipePose || mode == .openPalm {
            candidatePose = mode
            candidateSince = time
            candidateY = sample.y
            let lastClear = mode == .openPalm ? lastPalmPoseTime : lastSwipePoseTime
            if time - lastClear >= config.strokePoseHold {
                mode = .other
                candidatePose = .other
            }
            return
        }
```

Also update the doc comment above `updateMode` so it says stroke mode **and palm mode** are sticky.

5. In `gestureEvents(for:at:dt:)`, immediately before the line `guard mode == config.scrollPose else { return [] }`, insert:

```swift
        if config.circleEnabled {
            if mode == .openPalm {
                if circle.add(x: sample.x, y: sample.y, at: time) {
                    return [.circle]
                }
            } else {
                circle.reset()
            }
        }
```

6. In `resetTracking()`, add `circle.reset()` next to the other resets.

- [ ] **Step 6: Keep the executable compiling until Task 5**

The `airswipe` target switches exhaustively over `Action` and `GestureEvent`. Add the minimal cases (Task 5 replaces them):

In `Sources/airswipe/Sinks.swift`, in `ConsoleSink.perform` after the `.scroll` case body, and in `CGEventSink.perform` after its `.scroll` case, add:

```swift
        case .toggleVoice:
            break
```

In `Sources/airswipe/main.swift`, in the event `switch event`, after `case .scroll:` / `break`, add:

```swift
        case .circle:
            break
```

- [ ] **Step 7: Run everything and confirm it passes**

Run: `swift build && swift test`
Expected: build succeeds; all tests pass, including the 11 new circle tests and the mapper test.
If `unclearPoseKeepsPalmMode` fails, check that `lastPalmPoseTime = time` was added at arming (Step 5.3).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: an open-palm circle emits .circle, which toggles voice recording"
```

---

### Task 5: Sinks, status item, flags

**Files:**
- Modify: `Sources/airswipe/Sinks.swift`
- Modify: `Sources/airswipe/StatusItem.swift`
- Modify: `Sources/airswipe/main.swift`

**Interfaces:**
- Consumes: `KeyChord.parse(_:)` and its fields (Task 2), `Action.toggleVoice`, `GestureEvent.circle`, `GestureConfig.circleEnabled`.
- Produces: `--voice` and `--voice-key <chord>`; `StatusItemController.setRecording(_:)`. These are the camera and OS layers, verified by building and by hand (like the existing `airswipe` target), not by unit tests.

- [ ] **Step 1: The status item shows a recording mark**

Replace the body of `Sources/airswipe/StatusItem.swift` below the imports with:

```swift
/// A menu-bar indicator so you can see when AirSwipe is listening, and when a voice
/// recording is assumed to be running. Must be created and updated on the main thread.
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var armed = false
    private var recording = false

    init(mode: String) {
        refresh()

        let menu = NSMenu()
        menu.addItem(withTitle: "AirSwipe (\(mode))", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AirSwipe",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        item.menu = menu
    }

    func setArmed(_ armed: Bool) {
        self.armed = armed
        if !armed { recording = false }
        refresh()
    }

    func setRecording(_ recording: Bool) {
        self.recording = recording
        refresh()
    }

    private func refresh() {
        item.button?.title = (armed ? "🖐 ON" : "🖐 ·") + (recording ? " 🎙" : "")
    }
}
```

- [ ] **Step 2: The dry-run sink prints, the live sink presses the key**

In `Sources/airswipe/Sinks.swift`:

1. `ConsoleSink`: store the chord text and print it. Add a property and change `init`:

```swift
    private let voiceKey: String
```

```swift
    init(style: CGEventSink.NavigationStyle, voiceKey: String) {
        self.style = style
        self.voiceKey = voiceKey
    }
```

and replace its `case .toggleVoice: break` with:

```swift
        case .toggleVoice:
            print("  -> would press the voice key (\(voiceKey)) to start or stop recording")
```

2. `CGEventSink`: add the chord and use it. Add a property and change `init`:

```swift
    private let voiceChord: KeyChord?
```

```swift
    init(style: NavigationStyle, invertScroll: Bool, voiceChord: KeyChord?) {
        self.style = style
        self.invertScroll = invertScroll
        self.voiceChord = voiceChord
    }
```

and replace its `case .toggleVoice: break` with:

```swift
        case .toggleVoice:
            if let chord = voiceChord {
                postKey(CGKeyCode(chord.keyCode), flags: chord.flags)
            }
```

3. At the end of the file add the flag conversion (kept here so `AirSwipeCore` stays free of CoreGraphics):

```swift

private extension KeyChord {
    var flags: CGEventFlags {
        var flags: CGEventFlags = []
        if control { flags.insert(.maskControl) }
        if option { flags.insert(.maskAlternate) }
        if command { flags.insert(.maskCommand) }
        if shift { flags.insert(.maskShift) }
        return flags
    }
}
```

- [ ] **Step 3: Flags, wiring and events in `main.swift`**

1. Above `struct Options`, add the default chord (use the chord recorded in Task 1 if it is not `meta+k`):

```swift
/// The key AirSwipe presses to start and stop Claude Code's voice input. The user binds
/// `voice:pushToTalk` to the same chord in ~/.claude/keybindings.json.
let defaultVoiceChord = "meta+k"
```

2. In `Options`, add:

```swift
    var voice = false
    var voiceKey = defaultVoiceChord
```

3. In `usage`, change the USAGE line to
`  airswipe [--live] [--voice] [--voice-key CHORD] [--history] [--invert-scroll] [--rate-scroll] [--no-mirror] [--debug]`,
add these OPTIONS lines after `--live`:

```
  --voice          An open-palm circle starts and stops Claude Code voice input by
                   pressing its voice key. Needs /voice tap and a matching keybinding.
  --voice-key KEY  The chord to press, like meta+k or ctrl+shift+v (default meta+k).
                   Implies --voice.
```

and add this line to GESTURES after the "Fist" line:

```
  Open palm, draw a circle                  start / stop voice input (needs --voice)
```

4. Replace `parseOptions` with a version that can read a value after a flag:

```swift
func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    var remaining = arguments.makeIterator()
    while let argument = remaining.next() {
        switch argument {
        case "--live": options.live = true
        case "--voice": options.voice = true
        case "--voice-key":
            guard let value = remaining.next(), KeyChord.parse(value) != nil else {
                fputs("airswipe: --voice-key needs a chord such as meta+k or ctrl+shift+v\n\n\(usage)\n", stderr)
                exit(2)
            }
            options.voice = true
            options.voiceKey = value
        case "--history": options.history = true
        case "--desktops": break // now the default; accepted so old commands still run
        case "--invert-scroll": options.invertScroll = true
        case "--rate-scroll": options.rateScroll = true
        case "--no-mirror": options.mirror = false
        case "--debug": options.debug = true
        case "-h", "--help":
            print(usage)
            exit(0)
        default:
            fputs("airswipe: unknown option '\(argument)'\n\n\(usage)\n", stderr)
            exit(2)
        }
    }
    return options
}
```

5. After `if options.rateScroll { ... }` add:

```swift
gestureConfig.circleEnabled = options.voice
```

6. Replace the two sink constructions:

```swift
    sink = CGEventSink(style: options.history ? .browserHistory : .desktops,
                       invertScroll: options.invertScroll,
                       voiceChord: options.voice ? KeyChord.parse(options.voiceKey) : nil)
} else {
    sink = ConsoleSink(style: options.history ? .browserHistory : .desktops,
                       voiceKey: options.voiceKey)
}
```

7. Next to `var armedNow = false`, add:

```swift
/// Whether a voice recording is assumed to be running: each circle flips it.
var recordingNow = false
```

8. In the event switch, in the `.disarmed` case add `recordingNow = false` right after `armedNow = false`, and replace the temporary `case .circle: break` with:

```swift
        case .circle:
            recordingNow.toggle()
            print("\(stamp(time))voice: \(recordingNow ? "start" : "stop") recording (circle)")
            let recording = recordingNow
            DispatchQueue.main.async { status.setRecording(recording) }
```

- [ ] **Step 4: Build and check the command line**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

Run: `swift run airswipe --help | grep -n "voice"`
Expected: lines for `--voice`, `--voice-key` and the circle gesture.

Run: `swift run airswipe --voice-key nonsense; echo "exit=$?"`
Expected: the "--voice-key needs a chord" message and `exit=2`.

Run: `swift test 2>&1 | tail -2`
Expected: all tests still pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: --voice presses Claude Code's voice key on an open-palm circle"
```

---

### Task 6: Docs and the live test

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-10-16-voice-circle-design.md`

- [ ] **Step 1: README**

1. In the gestures table add a row after the fist row:
`| ✋ Open palm, draw a circle (with `--voice`) | **Start / stop voice input** in Claude Code |`
2. Add a section after "Fine scroll follows your hand" titled **Voice input for Claude Code**, explaining: one circle starts, the next stops; it presses Claude Code's own push-to-talk key, so AirSwipe records no audio; it is off unless `--voice`; and the one-time setup:

```text
1. In Claude Code run /voice tap
2. Create ~/.claude/keybindings.json containing
   { "bindings": [ { "context": "Chat", "bindings": { "meta+k": "voice:pushToTalk" } } ] }
3. In Terminal.app turn on Settings > Profiles > Keyboard > "Use Option as Meta key"
4. airswipe --live --voice
```

3. Add `--voice` and `--voice-key` rows to the Options table, and a Known limits bullet: works only while a terminal running Claude Code is focused, needs a claude.ai login and microphone permission for that terminal app, and the 🎙 mark is an assumption that can drift if Claude Code stops by itself.
4. Add troubleshooting rows: "The circle does nothing" (arm first, use an open palm, draw it within 1.5 s, at least 0.10 across, check `--debug` for `mode=openPalm`) and "The circle fires but Claude Code does not record" (check `/voice tap` is on, the keybinding chord matches `--voice-key`, Option is set as Meta, and Accessibility is allowed for the terminal app).
5. Update the test count in "Status" to the number `swift test` prints.

- [ ] **Step 2: Spec**

In `docs/superpowers/specs/2026-10-16-voice-circle-design.md`: change the status line to "implemented", add `backslash` / `\` to the chord key list in the Plumbing section (letters, digits, `space`, `\`, `f1` to `f20`), state the default chord chosen in Task 1, and link `docs/superpowers/spike-voice-key.md`.

- [ ] **Step 3: Verify and commit**

Run: `swift test 2>&1 | tail -2` — expect all pass.

```bash
git add -A
git commit -m "docs: voice circle in the README, spec marked implemented"
```

- [ ] **Step 4: Live test (with the user)**

Ask the user to run, in Terminal.app, with `/voice tap` on and the keybinding in place:

```bash
cd ~/Desktop/AirSwipe && swift run airswipe --live --voice --debug 2>&1 | tee debug.log
```

Expected, in order: arm with the palm and see `armed`; draw a palm circle and see `voice: start recording (circle)`, the 🎙 mark in the menu bar, and Claude Code recording; speak; draw another circle and see `voice: stop recording (circle)` and the transcript in the prompt box. Then check the same circle drawn with one finger causes swipes and flicks only, never `voice:`. If circles are missed or fire by accident, tune `circleMinTurn`, `circleMinSize` and `circleWindow` from `debug.log` (the palm path is in the `x=` and `y=` fields), re-run `swift test`, and commit.
