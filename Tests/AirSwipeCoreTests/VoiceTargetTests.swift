import Testing
import AirSwipeCore

@Suite("VoiceTarget")
struct VoiceTargetTests {
    private let claude = "com.anthropic.claudefordesktop"

    // Field evidence (live test, 2026-10-16): the start circle always brought the Claude app
    // forward, so circling on a YouTube page switched the whole screen over to Claude. The
    // default must dictate where the user already is.
    @Test("auto leaves another app alone, so the circle never switches screens")
    func autoStaysPut() {
        let target = VoiceTarget.auto
        #expect(!target.focusesClaude(frontmostBundleID: "com.google.Chrome", claudeBundleID: claude))
        #expect(!target.focusesClaude(frontmostBundleID: "com.apple.Safari", claudeBundleID: claude))
        #expect(!target.focusesClaude(frontmostBundleID: nil, claudeBundleID: claude))
    }

    @Test("auto still puts the cursor in the message box when Claude is the app in front")
    func autoFocusesInsideClaude() {
        #expect(VoiceTarget.auto.focusesClaude(frontmostBundleID: claude, claudeBundleID: claude))
    }

    @Test("claude always brings the Claude app forward")
    func claudeAlways() {
        let target = VoiceTarget.claude
        #expect(target.focusesClaude(frontmostBundleID: "com.google.Chrome", claudeBundleID: claude))
        #expect(target.focusesClaude(frontmostBundleID: claude, claudeBundleID: claude))
        #expect(target.focusesClaude(frontmostBundleID: nil, claudeBundleID: claude))
    }

    @Test("frontmost never touches focus, not even inside Claude")
    func frontmostNever() {
        let target = VoiceTarget.frontmost
        #expect(!target.focusesClaude(frontmostBundleID: claude, claudeBundleID: claude))
        #expect(!target.focusesClaude(frontmostBundleID: "com.google.Chrome", claudeBundleID: claude))
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
