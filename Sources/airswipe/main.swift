import AirSwipeCore
import AppKit
import Foundation

// MARK: - Options

struct Options {
    var live = false
    var history = false
    var invertScroll = false
    var rateScroll = false
    var mirror = true
    var debug = false
}

let usage = """
airswipe: switch screens and scroll by moving your hand in the air.

USAGE
  airswipe [--live] [--history] [--invert-scroll] [--rate-scroll] [--no-mirror] [--debug]

OPTIONS
  (default)        Dry run. Prints what it would do and posts nothing.
  --live           Post real key and scroll events (needs Accessibility permission).
  --history        Swipes go back/forward inside an app (Cmd+[ / Cmd+]) instead of
                   switching screens.
  --invert-scroll  Flip the scroll direction.
  --rate-scroll    Scroll by hand height (speed) instead of following the hand.
  --no-mirror      Do not mirror the camera horizontally.
  --debug          Print what the camera layer sees about ten times a second.
  -h, --help       Show this help.

GESTURES (the number of fingers is the command)
  Open palm, held still for half a second   START (menu-bar icon shows ON)
  One finger, move right / left             switch screen: like a 3- or 4-finger
                                            trackpad swipe between full-screen apps
                                            and desktops
  One finger, flick up / down               scroll: the page follows your hand, so the
                                            farther you flick the more it scrolls
  Two fingers, move your hand up / down     fine scroll: the page follows your hand
  Fist, held still for half a second        STOP
"""

func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    for argument in arguments {
        switch argument {
        case "--live": options.live = true
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

// MARK: - Wiring

// Piped output (`| tee log`) is block-buffered by default, which would hold lines
// back and lose the tail on Ctrl-C. Flush at every newline instead.
setvbuf(stdout, nil, _IOLBF, 0)

let options = parseOptions(Array(CommandLine.arguments.dropFirst()))

var gestureConfig = GestureConfig()
if options.rateScroll {
    gestureConfig.scrollMode = .rate
}

let engine = GestureEngine(config: gestureConfig)
let mapper = ActionMapper()
let tracker = HandTracker(mirrorX: options.mirror, collectDiagnostics: options.debug)

let sink: ActionSink
if options.live {
    if !CGEventSink.requestAccessibility() {
        fputs("""
            airswipe: Accessibility permission is not granted yet, so key and scroll
            events will be ignored. Allow your terminal app in System Settings >
            Privacy & Security > Accessibility, then run again.

            """, stderr)
    }
    sink = CGEventSink(style: options.history ? .browserHistory : .desktops,
                       invertScroll: options.invertScroll)
} else {
    sink = ConsoleSink(style: options.history ? .browserHistory : .desktops)
}

NSApplication.shared.setActivationPolicy(.accessory)
let status = StatusItemController(mode: options.live ? "live" : "dry run")

// Diagnostics state (used only with --debug). Touched only on the camera queue.
var debugOrigin: Double?
var debugFrames = 0
var debugLastPrint = 0.0
/// The latest move the engine turned down since the last debug line, so a
/// rejection that lasts one frame still shows up.
var debugRejection: String?
var armedNow = false

/// "[ 12.3s] " in debug mode, so events can be lined up with the frame lines.
func stamp(_ time: Double) -> String {
    guard options.debug, let origin = debugOrigin else { return "" }
    return String(format: "[%5.1fs] ", time - origin)
}

// Runs on the camera queue, once per frame: camera -> Vision -> engine -> action.
let camera = CameraSource { pixelBuffer, time in
    if debugOrigin == nil {
        debugOrigin = time
        debugLastPrint = time
    }
    let sample = tracker.sample(from: pixelBuffer)

    if options.debug {
        debugFrames += 1
        if time - debugLastPrint >= 0.1 {
            let fps = Double(debugFrames) / (time - debugLastPrint)
            let state = armedNow ? "ARMED" : "idle "
            let rejection = debugRejection.map { " | REJECTED \($0)" } ?? ""
            let line = "\(Int(fps.rounded()))fps \(engine.diagnostics) | \(tracker.diagnostics)\(rejection)"
            print("\(stamp(time))\(state) \(line)")
            debugFrames = 0
            debugLastPrint = time
            debugRejection = nil
        }
    }

    let events = engine.process(sample, at: time)
    if options.debug, let rejection = engine.lastRejection {
        debugRejection = rejection
    }

    for event in events {
        switch event {
        case .armed:
            armedNow = true
            print("\(stamp(time))armed: hand gestures are on")
            DispatchQueue.main.async { status.setArmed(true) }
        case .disarmed:
            armedNow = false
            let why: String
            switch engine.lastDisarmReason {
            case .fist?: why = "fist held"
            case .handLost?: why = "hand out of view"
            case .idle?: why = "idle too long"
            case nil: why = "unknown"
            }
            print("\(stamp(time))disarmed (\(why))")
            DispatchQueue.main.async { status.setArmed(false) }
        case .swipe(let direction):
            print("\(stamp(time))swipe \(direction == .right ? "right" : "left")")
        case .flick(let direction):
            print("\(stamp(time))flick \(direction == .up ? "up" : "down")")
        case .scroll:
            break
        case .circle:
            break
        }
        for action in mapper.actions(for: event) {
            sink.perform(action)
        }
    }

    sink.endFrame()
}

do {
    try camera.start()
} catch {
    fputs("airswipe: \(error)\n", stderr)
    exit(1)
}

print("airswipe is running (\(options.live ? "LIVE" : "dry run")). Hold an open palm still to arm.")
print("Quit from the menu-bar item, or press Ctrl-C.")

NSApplication.shared.run()
