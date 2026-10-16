import AirSwipeCore
import ApplicationServices
import AppKit
import Foundation

/// Puts the cursor in a web page's own text box, because a hand in the air cannot click one.
///
/// Dictation only types into the box that has the cursor. By hand it works in a browser; what
/// was missing was the click. This finds the page's search box (Google, YouTube and most
/// sites have one) through the macOS accessibility API and focuses it, the same technique
/// `ClaudePromptFocus` uses for the Claude app. A box the user already clicked is left alone.
///
/// Chromium browsers (Chrome, Edge, Brave, Arc) only expose a page's contents to the
/// accessibility API after being asked, which `prepare()` does; the tree can take a moment
/// to build. Safari exposes it already.
final class WebTextFocus {
    static let browserBundleIdentifiers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "company.thebrowser.Browser", // Arc
        "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "org.mozilla.firefox",
    ]

    enum Outcome: CustomStringConvertible {
        /// The user already had the cursor in a text box: left alone.
        case alreadyInTextBox
        case focused(label: String)
        case noTextBoxFound
        /// The page's contents are not in the accessibility tree (yet).
        case noPageContent
        case failed(Int32)

        /// True when the cursor is in a text box now.
        var isInTextBox: Bool {
            switch self {
            case .alreadyInTextBox, .focused: return true
            default: return false
            }
        }

        var description: String {
            switch self {
            case .alreadyInTextBox:
                return "a text box already has the cursor, left it alone"
            case .focused(let label):
                return label.isEmpty ? "put the cursor in the page's text box"
                                     : "put the cursor in the page's text box (\"\(label)\")"
            case .noTextBoxFound:
                return "could not find a text box on the page"
            case .noPageContent:
                return "the browser has not exposed the page to accessibility yet; try again in a few seconds"
            case .failed(let code):
                return "the browser refused to focus the text box (accessibility error \(code))"
            }
        }
    }

    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"]

    /// Asks every running browser to expose its pages to accessibility. Call once at
    /// startup so the first circle does not wait for the tree to build.
    func prepare() {
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, Self.browserBundleIdentifiers.contains(id) else { continue }
            enableAccessibility(AXUIElementCreateApplication(app.processIdentifier))
        }
    }

    /// Focuses the page's text box in `app`. Blocks for up to a few seconds, so call it off
    /// the camera thread.
    func focus(app: NSRunningApplication) -> Outcome {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        enableAccessibility(root)

        // A box the user already clicked stays theirs.
        if let focused = attribute(root, kAXFocusedUIElementAttribute),
           Self.textRoles.contains(text(focused as! AXUIElement, kAXRoleAttribute)) {
            return .alreadyInTextBox
        }

        // Right after a page loads, or the first time, the tree may still be building.
        var outcome = Outcome.noPageContent
        for attempt in 0..<3 {
            outcome = focusOnce(root)
            if case .noPageContent = outcome, attempt < 2 {
                Thread.sleep(forTimeInterval: 0.8)
                continue
            }
            break
        }
        return outcome
    }

    private func focusOnce(_ root: AXUIElement) -> Outcome {
        let window = (attribute(root, kAXFocusedWindowAttribute) as! AXUIElement?)
            ?? (attribute(root, kAXWindowsAttribute) as? [AXUIElement])?.first
        guard let window else { return .noPageContent }

        var elements: [AXUIElement] = []
        var candidates: [TextFieldCandidate] = []
        var sawWebContent = false
        var visited = 0
        let deadline = Date().addingTimeInterval(2)

        func walk(_ element: AXUIElement, inWeb: Bool, depth: Int) -> Bool {
            guard depth < 60, visited < 12000, Date() < deadline else { return false }
            visited += 1
            let role = text(element, kAXRoleAttribute)
            let isWeb = inWeb || role == "AXWebArea"
            if role == "AXWebArea" { sawWebContent = true }

            if Self.textRoles.contains(role) {
                let label = [kAXTitleAttribute, kAXDescriptionAttribute, "AXPlaceholderValue", kAXHelpAttribute]
                    .map { text(element, $0) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let size = self.size(element)
                let enabled = (attribute(element, kAXEnabledAttribute) as? Bool) ?? true
                let candidate = TextFieldCandidate(role: role, label: label, isInWebContent: isWeb,
                                                   isEnabled: enabled,
                                                   width: Double(size.width), height: Double(size.height))
                elements.append(element)
                candidates.append(candidate)
                // A box that says "search" in the page cannot be beaten: stop looking.
                if isWeb, enabled, size.width >= 40, size.height >= 10,
                   label.lowercased().contains("search") {
                    return true
                }
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                for child in children where walk(child, inWeb: isWeb, depth: depth + 1) {
                    return true
                }
            }
            return false
        }
        _ = walk(window, inWeb: false, depth: 0)

        guard sawWebContent else { return .noPageContent }
        guard let index = TextFieldChoice.best(in: candidates) else { return .noTextBoxFound }
        let result = AXUIElementSetAttributeValue(elements[index], kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return result == .success ? .focused(label: candidates[index].label) : .failed(result.rawValue)
    }

    private func enableAccessibility(_ root: AXUIElement) {
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private func text(_ element: AXUIElement, _ name: String) -> String {
        attribute(element, name) as? String ?? ""
    }

    private func size(_ element: AXUIElement) -> CGSize {
        guard let value = attribute(element, kAXSizeAttribute) else { return .zero }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size
    }
}
