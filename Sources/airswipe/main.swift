import AirSwipeCore
import AppKit
import Foundation

// MARK: - Options

struct Options {
    var live = false
    var desktops = false
    var invertScroll = false
    var mirror = true
}

let usage = """
airswipe: change pages and scroll by moving your hand in the air.

USAGE
  airswipe [--live] [--desktops] [--invert-scroll] [--no-mirror]

OPTIONS
  (default)        Dry run. Prints what it would do and posts nothing.
  --live           Post real key and scroll events (needs Accessibility permission).
  --desktops       Swipes switch desktops (Ctrl+Left/Right) instead of back/forward.
  --invert-scroll  Flip the scroll direction.
  --no-mirror      Do not mirror the camera horizontally.
  -h, --help       Show this help.

GESTURES
  Hold an open palm still for half a second   arms it (menu-bar icon shows ON)
  Swipe your hand right / left                back / forward
  Raise / lower your hand from where you armed  scroll up / down
  Make a fist, or lower your hand out of view   disarms it
"""

func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    for argument in arguments {
        switch argument {
        case "--live": options.live = true
        case "--desktops": options.desktops = true
        case "--invert-scroll": options.invertScroll = true
        case "--no-mirror": options.mirror = false
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

let options = parseOptions(Array(CommandLine.arguments.dropFirst()))

let engine = GestureEngine()
let mapper = ActionMapper()
let tracker = HandTracker(mirrorX: options.mirror)

let sink: ActionSink
if options.live {
    if !CGEventSink.requestAccessibility() {
        fputs("""
            airswipe: Accessibility permission is not granted yet, so key and scroll
            events will be ignored. Allow your terminal app in System Settings >
            Privacy & Security > Accessibility, then run again.

            """, stderr)
    }
    sink = CGEventSink(style: options.desktops ? .desktops : .browserHistory,
                       invertScroll: options.invertScroll)
} else {
    sink = ConsoleSink()
}

NSApplication.shared.setActivationPolicy(.accessory)
let status = StatusItemController(mode: options.live ? "live" : "dry run")

// Runs on the camera queue, once per frame: camera -> Vision -> engine -> action.
let camera = CameraSource { pixelBuffer, time in
    let sample = tracker.sample(from: pixelBuffer)
    for event in engine.process(sample, at: time) {
        switch event {
        case .armed:
            print("armed: hand gestures are on")
            DispatchQueue.main.async { status.setArmed(true) }
        case .disarmed:
            print("disarmed")
            DispatchQueue.main.async { status.setArmed(false) }
        case .swipe(let direction):
            print("swipe \(direction == .right ? "right" : "left")")
        case .scroll:
            break
        }
        for action in mapper.actions(for: event) {
            sink.perform(action)
        }
    }
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
