import Testing
import AirSwipeCore

// Dictation only types into the text box that has the cursor, and a hand in the air cannot
// click. When the app in front is a browser and no box is focused, AirSwipe finds the page's
// own search box through the accessibility tree and focuses it. The tree has several boxes
// (the address bar, a comment box, hidden inputs); this decides which one is meant.
@Suite("TextFieldChoice")
struct TextFieldChoiceTests {
    private func field(_ role: String = "AXTextField", label: String = "",
                       web: Bool = true, enabled: Bool = true,
                       width: Double = 300, height: Double = 30) -> TextFieldCandidate {
        TextFieldCandidate(role: role, label: label, isInWebContent: web, isEnabled: enabled,
                           width: width, height: height)
    }

    @Test("the box labelled search wins over an earlier plain one")
    func searchLabelWins() {
        let fields = [field(label: "Add a comment"), field(label: "Search"), field(label: "Reply")]
        #expect(TextFieldChoice.best(in: fields) == 1)
    }

    @Test("a label is matched in any case and as part of longer words")
    func labelMatchingIsLoose() {
        let fields = [field(label: "email"), field(label: "Voice SEARCH query")]
        #expect(TextFieldChoice.best(in: fields) == 1)
    }

    @Test("a search-type field wins when no label says search")
    func searchRoleWins() {
        let fields = [field("AXTextField", label: "name"), field("AXSearchField", label: "")]
        #expect(TextFieldChoice.best(in: fields) == 1)
    }

    @Test("a label that says search beats a search-type field with no label")
    func labelBeatsRole() {
        let fields = [field("AXSearchField", label: ""), field("AXTextArea", label: "Search Google")]
        #expect(TextFieldChoice.best(in: fields) == 1)
    }

    @Test("with nothing that says search, the first box on the page is chosen")
    func firstWins() {
        let fields = [field("AXTextArea", label: "message"), field("AXTextField", label: "name")]
        #expect(TextFieldChoice.best(in: fields) == 0)
    }

    @Test("combo boxes count: Google's search box is one")
    func comboBoxIsAllowed() {
        #expect(TextFieldChoice.best(in: [field("AXComboBox", label: "Search")]) == 0)
    }

    @Test("the browser's own address bar is never chosen, only boxes in the page")
    func addressBarIsSkipped() {
        let fields = [field(label: "Address and search bar", web: false), field(label: "Comment")]
        #expect(TextFieldChoice.best(in: fields) == 1)
        #expect(TextFieldChoice.best(in: [field(label: "Address and search bar", web: false)]) == nil)
    }

    @Test("disabled, tiny and zero-size boxes are skipped")
    func unusableBoxesAreSkipped() {
        let fields = [
            field(label: "Search", enabled: false),
            field(label: "Search", width: 0, height: 0),
            field(label: "Search", width: 20, height: 4),
            field(label: "Comment"),
        ]
        #expect(TextFieldChoice.best(in: fields) == 3)
    }

    @Test("things that are not text boxes are ignored")
    func otherRolesAreIgnored() {
        #expect(TextFieldChoice.best(in: [field("AXButton", label: "Search"), field("AXStaticText", label: "Search")]) == nil)
    }

    @Test("a page with no box gives nothing")
    func noBox() {
        #expect(TextFieldChoice.best(in: []) == nil)
    }
}
