import Foundation

/// Where voice dictation goes, and so whether the Claude app is brought into the picture.
///
/// Dictation types into whichever text field has the cursor. The Claude desktop app has no
/// shortcut to focus its message box, so AirSwipe can focus it through the accessibility
/// API. That also brings the app forward, which switches the whole screen when Claude is
/// on another desktop or in its own full screen. Doing that every time was wrong for
/// someone circling on a YouTube page who wants to dictate into the page they are on.
public enum VoiceTarget: Equatable {
    /// Where you are. Dictation goes into the app in front, and the send key (Return) too.
    /// Only when that app is the Claude app is its message box focused first, so no click is
    /// needed there and the screen never switches. This is the default.
    case auto
    /// Always bring the Claude app forward and put the cursor in its message box, from
    /// anywhere. The screen switches to Claude if it lives on another desktop.
    case claude
    /// Never touch focus: press the keys into whatever is focused, even inside Claude.
    case frontmost

    /// Whether to focus the Claude message box before pressing a key.
    /// - Parameters:
    ///   - frontmostBundleID: the app in front right now, if known.
    ///   - claudeBundleID: the Claude app's bundle identifier.
    public func focusesClaude(frontmostBundleID: String?, claudeBundleID: String) -> Bool {
        switch self {
        case .auto: return frontmostBundleID == claudeBundleID
        case .claude: return true
        case .frontmost: return false
        }
    }

    /// The word used on the command line: `auto`, `claude` or `frontmost`.
    public init?(argument: String) {
        switch argument {
        case "auto": self = .auto
        case "claude": self = .claude
        case "frontmost": self = .frontmost
        default: return nil
        }
    }
}
