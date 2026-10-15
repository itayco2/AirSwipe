import AppKit

/// A menu-bar indicator so you can see when AirSwipe is listening.
/// Must be created and updated on the main thread.
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init(mode: String) {
        setArmed(false)

        let menu = NSMenu()
        menu.addItem(withTitle: "AirSwipe (\(mode))", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AirSwipe",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        item.menu = menu
    }

    func setArmed(_ armed: Bool) {
        item.button?.title = armed ? "🖐 ON" : "🖐 ·"
    }
}
