import ApplicationServices
import AppKit
import Foundation

/// Puts the cursor in the Claude desktop app's message box, so a dictation key press
/// lands there with no click.
///
/// The app is built on Chromium, which exposes its interface to the macOS accessibility
/// API only after being asked, and takes several seconds to build that tree. Once it is
/// built, the message box is a text area labelled "Prompt" (found with a probe on
/// 2026-10-16; see docs/superpowers/spike-voice-key.md).
final class ClaudePromptFocus {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"

    enum Outcome: CustomStringConvertible {
        case focused
        case appNotRunning
        case boxNotFound
        case failed(Int32)

        var isFocused: Bool {
            if case .focused = self { return true }
            return false
        }

        var description: String {
            switch self {
            case .focused:
                return "focused the Claude message box"
            case .appNotRunning:
                return "the Claude app is not running"
            case .boxNotFound:
                return "could not find the message box in the Claude app's accessibility tree"
            case .failed(let code):
                return "the Claude app refused to focus the message box (accessibility error \(code))"
            }
        }
    }

    private var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first
    }

    /// Asks the app to build its accessibility tree. Call once at startup so the first
    /// circle does not wait for it. Returns false if the app is not running.
    @discardableResult
    func prepare() -> Bool {
        guard let app = runningApp else { return false }
        enableAccessibility(AXUIElementCreateApplication(app.processIdentifier))
        return true
    }

    /// Brings the app forward and focuses its message box. Blocks for up to a few
    /// seconds, so call it off the camera thread.
    func focus() -> Outcome {
        guard let app = runningApp else { return .appNotRunning }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        enableAccessibility(root)
        AXUIElementSetAttributeValue(root, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.15)

        // Right after the app starts the tree may still be building, so look a few times.
        var box: AXUIElement?
        for attempt in 0..<4 {
            box = findPromptBox(in: root)
            if box != nil { break }
            if attempt < 3 { Thread.sleep(forTimeInterval: 1.0) }
        }
        guard let box else { return .boxNotFound }
        let result = AXUIElementSetAttributeValue(box, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return result == .success ? .focused : .failed(result.rawValue)
    }

    private func enableAccessibility(_ root: AXUIElement) {
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// The text area labelled "Prompt"; failing that, the lowest text area on screen.
    private func findPromptBox(in root: AXUIElement) -> AXUIElement? {
        var labelled: AXUIElement?
        var lowest: (element: AXUIElement, top: CGFloat)?
        var visited = 0
        let deadline = Date().addingTimeInterval(2)

        func walk(_ element: AXUIElement, depth: Int) {
            guard labelled == nil, depth < 40, visited < 8000, Date() < deadline else { return }
            visited += 1
            if text(element, kAXRoleAttribute) == "AXTextArea" {
                let names = [kAXDescriptionAttribute, "AXPlaceholderValue", kAXTitleAttribute]
                    .map { text(element, $0).lowercased() }
                if names.contains(where: { $0.contains("prompt") }) {
                    labelled = element
                    return
                }
                let top = position(element)?.y ?? 0
                if lowest == nil || top > lowest!.top { lowest = (element, top) }
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                for child in children { walk(child, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return labelled ?? lowest?.element
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private func text(_ element: AXUIElement, _ name: String) -> String {
        attribute(element, name) as? String ?? ""
    }

    private func position(_ element: AXUIElement) -> CGPoint? {
        guard let value = attribute(element, kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }
}
