import Foundation

/// What to put the cursor in before the dictation key is pressed.
public enum VoiceFocus: Equatable {
    /// Leave focus alone: the user put the cursor where they want it.
    case none
    /// The Claude app's message box (found through accessibility, since the app has no shortcut).
    case claudeMessageBox
    /// The page's own text box, usually its search box. A hand in the air cannot click one.
    case webTextField
}

/// Where voice dictation goes, and so whether the Claude app is brought into the picture.
///
/// Dictation types into whichever text field has the cursor. The Claude desktop app has no
/// shortcut to focus its message box, so AirSwipe can focus it through the accessibility
/// API. That also brings the app forward, which switches the whole screen when Claude is
/// on another desktop or in its own full screen. Doing that every time was wrong for
/// someone circling on a YouTube page who wants to dictate into the page they are on.
public enum VoiceTarget: Equatable {
    /// Where you are. Dictation goes into the app in front, and the send key (Return) too.
    /// Where a hand cannot click, the cursor is put in the right box first: the message box
    /// when that app is Claude, the page's own text box when it is a browser (unless a box
    /// already has the cursor). The screen never switches. This is the default.
    case auto
    /// Always bring the Claude app forward and put the cursor in its message box, from
    /// anywhere. The screen switches to Claude if it lives on another desktop.
    case claude
    /// Never touch focus: press the keys into whatever is focused, even inside Claude.
    case frontmost

    /// What to put the cursor in before pressing a key.
    /// - Parameters:
    ///   - frontmostBundleID: the app in front right now, if known.
    ///   - claudeBundleID: the Claude app's bundle identifier.
    ///   - browserBundleIDs: the bundle identifiers of the web browsers.
    public func focus(frontmostBundleID: String?, claudeBundleID: String,
                      browserBundleIDs: Set<String>) -> VoiceFocus {
        switch self {
        case .auto:
            guard let app = frontmostBundleID else { return .none }
            if app == claudeBundleID { return .claudeMessageBox }
            if browserBundleIDs.contains(app) { return .webTextField }
            return .none
        case .claude:
            return .claudeMessageBox
        case .frontmost:
            return .none
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
