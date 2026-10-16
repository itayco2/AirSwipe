import AppKit

/// A menu-bar indicator so you can see when AirSwipe is listening, and when voice
/// dictation is assumed to be running. Must be created and updated on the main thread.
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
