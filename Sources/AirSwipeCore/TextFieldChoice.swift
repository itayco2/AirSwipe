import Foundation

/// A text box found in an app's accessibility tree, described without any AppKit type so
/// the choice between boxes can be tested with plain values.
public struct TextFieldCandidate: Equatable {
    /// The accessibility role: `AXTextField`, `AXTextArea`, `AXSearchField` or `AXComboBox`.
    public var role: String
    /// Everything the box says about itself (title, description, placeholder), joined.
    public var label: String
    /// True for a box inside the web page, false for the browser's own (the address bar).
    public var isInWebContent: Bool
    public var isEnabled: Bool
    public var width: Double
    public var height: Double

    public init(role: String, label: String, isInWebContent: Bool, isEnabled: Bool,
                width: Double, height: Double) {
        self.role = role
        self.label = label
        self.isInWebContent = isInWebContent
        self.isEnabled = isEnabled
        self.width = width
        self.height = height
    }
}

/// Picks the box dictation should go into when the user has not clicked one.
///
/// Dictation only types into the box that has the cursor, and a hand in the air cannot
/// click. In a browser the page's search box is almost always what is wanted (Google,
/// YouTube, and most sites put it first), so a box that says "search" wins, then a
/// search-type field, then simply the first usable box on the page. The browser's own
/// address bar is skipped: it is not in the page.
public enum TextFieldChoice {
    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"]
    /// Anything smaller is a hidden or decorative input, not something a person types into.
    private static let minimumSize = (width: 40.0, height: 10.0)

    /// The index of the best box in `candidates`, which are in the order they appear in the
    /// page, or nil if none is usable.
    public static func best(in candidates: [TextFieldCandidate]) -> Int? {
        var best: (index: Int, rank: Int)?
        for (index, candidate) in candidates.enumerated() {
            guard textRoles.contains(candidate.role),
                  candidate.isInWebContent,
                  candidate.isEnabled,
                  candidate.width >= minimumSize.width,
                  candidate.height >= minimumSize.height else { continue }

            let rank: Int
            if candidate.label.lowercased().contains("search") {
                rank = 0
            } else if candidate.role == "AXSearchField" {
                rank = 1
            } else {
                rank = 2
            }
            // Strictly better only, so among equals the earlier box (higher on the page) wins.
            if best == nil || rank < best!.rank {
                best = (index, rank)
            }
        }
        return best?.index
    }
}
