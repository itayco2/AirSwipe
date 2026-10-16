import Testing
import AirSwipeCore

@Suite("VoiceTarget")
struct VoiceTargetTests {
    private let claude = "com.anthropic.claudefordesktop"
    private let browsers: Set<String> = ["com.google.Chrome", "com.apple.Safari"]

    private func focus(_ target: VoiceTarget, in app: String?) -> VoiceFocus {
        target.focus(frontmostBundleID: app, claudeBundleID: claude, browserBundleIDs: browsers)
    }

    // Field evidence (live test, 2026-10-16): the start circle always brought the Claude app
    // forward, so circling on a YouTube page switched the whole screen over to Claude. The
    // default must dictate where the user already is.
    @Test("auto leaves another app alone, so the circle never switches screens")
    func autoStaysPut() {
        #expect(focus(.auto, in: "com.apple.Notes") == .none)
        #expect(focus(.auto, in: nil) == .none)
    }

    @Test("auto still puts the cursor in the message box when Claude is the app in front")
    func autoFocusesInsideClaude() {
        #expect(focus(.auto, in: claude) == .claudeMessageBox)
    }

    // Dictation by hand worked in Chrome; what was missing was the click. A hand in the air
    // cannot click, so in a browser AirSwipe puts the cursor in the page's search box itself.
    @Test("auto in a browser focuses the page's own text box, since a hand cannot click")
    func autoFocusesTheWebPage() {
        #expect(focus(.auto, in: "com.google.Chrome") == .webTextField)
        #expect(focus(.auto, in: "com.apple.Safari") == .webTextField)
    }

    @Test("claude always brings the Claude app forward")
    func claudeAlways() {
        #expect(focus(.claude, in: "com.google.Chrome") == .claudeMessageBox)
        #expect(focus(.claude, in: claude) == .claudeMessageBox)
        #expect(focus(.claude, in: nil) == .claudeMessageBox)
    }

    @Test("frontmost never touches focus, not even inside Claude or a browser")
    func frontmostNever() {
        #expect(focus(.frontmost, in: claude) == .none)
        #expect(focus(.frontmost, in: "com.google.Chrome") == .none)
    }

    @Test("the command-line words map to the three targets")
    func parsing() {
        #expect(VoiceTarget(argument: "auto") == .auto)
        #expect(VoiceTarget(argument: "claude") == .claude)
        #expect(VoiceTarget(argument: "frontmost") == .frontmost)
        #expect(VoiceTarget(argument: "Claude") == nil)
        #expect(VoiceTarget(argument: "") == nil)
        #expect(VoiceTarget(argument: "elsewhere") == nil)
    }
}
