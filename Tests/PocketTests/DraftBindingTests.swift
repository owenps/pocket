import AppKit
import Observation
import PocketTestSupport
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct DraftBindingTests {
    @Test func nativeEditsUndoAndRestorationKeepTheOwnedDraftSynchronized() async throws {
        _ = NSApplication.shared
        let draft = BoundDraft()
        let fixture = OffscreenHost(BoundDraftEditor(draft: draft), size: CGSize(width: 360, height: 100))
        defer { fixture.close() }
        let host = fixture.view
        let window = fixture.window
        try await AsyncTestSupport.wait {
            host.layoutSubtreeIfNeeded()
            return window.firstResponder is DraftTextView
        }
        let editor = try #require(window.firstResponder as? DraftTextView)
        editor.insertText("Hello", replacementRange: editor.selectedRange())
        #expect(draft.text == "Hello")
        editor.deleteBackward(nil)
        #expect(draft.text == "Hell")
        editor.insertNewline(nil)
        #expect(draft.text == "Hell\n")

        let undo = try #require(editor.undoManager)
        let groupsByEvent = undo.groupsByEvent
        undo.groupsByEvent = false
        defer { undo.groupsByEvent = groupsByEvent }
        undo.removeAllActions()
        undo.beginUndoGrouping()
        editor.insertText("next", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        undo.endUndoGrouping()
        #expect(draft.text == "Hell\nnext")
        undo.undo()
        #expect(draft.text == "Hell\n")
        undo.redo()
        #expect(draft.text == "Hell\nnext")

        draft.text = "Restored draft"
        try await AsyncTestSupport.wait {
            host.layoutSubtreeIfNeeded()
            return editor.string == "Restored draft"
        }
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        undo.beginUndoGrouping()
        editor.insertText(" updated", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        undo.endUndoGrouping()
        #expect(draft.text == "Restored draft updated")
        #expect(window.firstResponder === editor)
    }
}

@MainActor
@Observable
private final class BoundDraft {
    var text = ""
}

private struct BoundDraftEditor: View {
    @Bindable var draft: BoundDraft

    var body: some View {
        DraftEditor(text: $draft.text, isEditing: true, focusRequest: 1, onHeightChange: { _ in })
    }
}
