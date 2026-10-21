import AppKit
import Testing
@testable import Pocket

@MainActor
struct DraftEditorTests {
    @Test func placeholderChangesOnReopenButNotDuringEditing() {
        let view = makeEditor(width: 360)
        view.setEditing(true, focusRequest: 1)
        let first = view.editor.placeholder
        #expect(view.editor.string.isEmpty)

        view.setEditing(true, focusRequest: 1)
        view.refreshLayout()
        #expect(view.editor.placeholder == first)

        view.setTextIfNeeded("Keep my draft")
        let selection = NSRange(location: 2, length: 4)
        view.editor.setSelectedRange(selection)
        view.setEditing(false, focusRequest: 1)
        view.setEditing(true, focusRequest: 2)
        #expect(view.editor.placeholder != first)
        #expect(view.editor.string == "Keep my draft")
        #expect(view.editor.selectedRange() == selection)
    }

    @Test(arguments: ["", "Owen"])
    func acceptedSendUsesGenericPlaceholderUntilReopened(name: String) {
        let view = makeEditor(width: 360)
        view.editor.userName = name
        view.setEditing(true, focusRequest: 1)
        let greeting = view.editor.placeholder
        view.setTextIfNeeded("Hello")
        view.editor.onSubmit = {
            view.setTextIfNeeded("")
            return true
        }

        view.editor.keyDown(with: NativeTextTestSupport.keyEvent())
        #expect(view.editor.string.isEmpty)
        #expect(view.editor.placeholder == "Send a message…")

        view.editor.userName = "Alex"
        view.setEditing(true, focusRequest: 2)
        view.refreshLayout()
        #expect(view.editor.placeholder == "Send a message…")

        view.setEditing(false, focusRequest: 2)
        view.setEditing(true, focusRequest: 3)
        #expect(view.editor.placeholder != "Send a message…")
        #expect(view.editor.placeholder != greeting)
    }

    @Test(arguments: ["", "Owen"])
    func rejectedSendKeepsOpeningGreeting(name: String) {
        let view = makeEditor(width: 360)
        view.editor.userName = name
        view.setEditing(true, focusRequest: 1)
        let greeting = view.editor.placeholder
        view.editor.onSubmit = { false }

        view.editor.keyDown(with: NativeTextTestSupport.keyEvent())
        #expect(view.editor.placeholder == greeting)
    }

    @Test func emptyAndShortDraftsUseCompactMinimum() {
        let view = makeEditor(width: 360)
        #expect(view.refreshLayout() == DraftEditor.minimumHeight)
        view.setTextIfNeeded("A short thought")
        #expect(view.refreshLayout() == DraftEditor.minimumHeight)
        #expect(view.acceptsFirstMouse(for: nil))
        #expect(view.editor.acceptsFirstMouse(for: nil))
    }

    @Test(arguments: [11.0, 17.0, 24.0])
    func compactHeightFollowsTheNativeFontRatherThanAFixedFloor(fontSize: Double) throws {
        let view = makeEditor(width: 360)
        view.setFontSize(fontSize)
        let emptyHeight = try #require(view.refreshLayout())
        #expect(emptyHeight == NativeTextTestSupport.height(of: view.editor))
        #expect(emptyHeight == DraftEditor.singleLineHeight(fontSize: fontSize))
        #expect(emptyHeight < 40)
        view.setTextIfNeeded("A short thought")
        #expect(view.refreshLayout() == emptyHeight)
        view.setTextIfNeeded("One\nTwo\nThree")
        #expect(try #require(view.refreshLayout()) > emptyHeight)
        view.setTextIfNeeded("")
        #expect(view.refreshLayout() == emptyHeight)
    }

    @Test func newlinesGrowUsingRenderedLayoutIncludingTrailingEmptyLine() throws {
        let view = makeEditor(width: 360)
        view.setTextIfNeeded("One\nTwo\nThree\nFour")
        let fourLines = try #require(view.refreshLayout())
        #expect(fourLines > DraftEditor.minimumHeight)
        #expect(fourLines < DraftEditor.maximumHeight)
        #expect(view.measuredContentHeight == NativeTextTestSupport.height(of: view.editor))

        view.setTextIfNeeded(view.editor.string + "\n")
        let fiveLines = try #require(view.refreshLayout())
        #expect(fiveLines > fourLines)
        #expect(view.measuredContentHeight == NativeTextTestSupport.height(of: view.editor))
        let manager = try #require(view.editor.layoutManager)
        #expect(manager.extraLineFragmentTextContainer === view.editor.textContainer)
    }

    @Test func widthChangesReflowTextWithoutDisturbingSelection() throws {
        let view = makeEditor(width: 480)
        let draft = Array(repeating: "A thought worth keeping", count: 8).joined(separator: " ")
        view.setTextIfNeeded(draft)
        view.refreshLayout()
        let wideHeight = try #require(view.measuredContentHeight)
        let selection = NSRange(location: 5, length: 7)
        view.editor.setSelectedRange(selection)

        view.setFrameSize(NSSize(width: 150, height: DraftEditor.minimumHeight))
        view.refreshLayout()
        let narrowHeight = try #require(view.measuredContentHeight)
        #expect(narrowHeight > wideHeight)
        #expect(narrowHeight == NativeTextTestSupport.height(of: view.editor))
        #expect(view.editor.string == draft)
        #expect(view.editor.selectedRange() == selection)
        #expect(view.editor.frame.width == view.contentView.bounds.width)
        #expect(view.editor.textContainer?.containerSize.width == view.editor.frame.width)

        view.setFrameSize(NSSize(width: 480, height: DraftEditor.minimumHeight))
        view.refreshLayout()
        #expect(view.measuredContentHeight == wideHeight)
    }

    @Test func longDraftCapsViewportButKeepsScrollableDocumentAndShrinksOnDeletion() throws {
        let view = makeEditor(width: 300)
        view.setTextIfNeeded(Array(repeating: "Another line", count: 30).joined(separator: "\n"))
        #expect(view.refreshLayout() == DraftEditor.maximumHeight)
        let naturalHeight = try #require(view.measuredContentHeight)
        #expect(naturalHeight > DraftEditor.maximumHeight)
        #expect(view.editor.frame.height == naturalHeight)
        #expect(!view.hasVerticalScroller)
        #expect(!view.hasHorizontalScroller)

        view.setFrameSize(NSSize(width: 300, height: DraftEditor.maximumHeight))
        view.setTextIfNeeded("Short again")
        #expect(view.refreshLayout() == DraftEditor.minimumHeight)
        #expect(view.measuredContentHeight == NativeTextTestSupport.height(of: view.editor))
        view.setFrameSize(NSSize(width: 300, height: DraftEditor.minimumHeight))
        view.refreshLayout()
        #expect(view.editor.frame.height == DraftEditor.minimumHeight)
    }

    @Test func keyboardNavigationScrollsLongDraftWithoutScrollbars() {
        let view = makeEditor(width: 300)
        view.setEditing(true, focusRequest: 1)
        view.setFrameSize(NSSize(width: 300, height: DraftEditor.maximumHeight))
        view.setTextIfNeeded(Array(repeating: "Another line", count: 40).joined(separator: "\n"))
        view.refreshLayout()
        view.editor.setSelectedRange(NSRange(location: 0, length: 0))

        view.editor.moveToEndOfDocument(nil)
        #expect(view.editor.selectedRange().location == view.editor.string.utf16.count)
        #expect(view.contentView.bounds.minY > 0)
        #expect(view.editor.visibleRect.maxY >= view.editor.frame.maxY - 2)
        view.editor.moveToBeginningOfDocument(nil)
        #expect(view.editor.selectedRange().location == 0)
        #expect(view.contentView.bounds.minY == 0)
        #expect(!view.hasVerticalScroller)
        #expect(!view.hasHorizontalScroller)
    }

    @Test func returnAndKeypadEnterSubmitOnceWithoutChangingNativeText() {
        for keyCode: UInt16 in [36, 76] {
            let view = makeEditor(width: 360)
            view.setEditing(true, focusRequest: 1)
            view.setTextIfNeeded("Send me")
            let selection = NSRange(location: 2, length: 3)
            view.editor.setSelectedRange(selection)
            var submissions = 0
            view.editor.onSubmit = {
                submissions += 1
                return true
            }

            view.editor.keyDown(with: NativeTextTestSupport.keyEvent(code: keyCode))
            #expect(submissions == 1)
            #expect(view.editor.string == "Send me")
            #expect(view.editor.selectedRange() == selection)
        }
    }

    @Test func rejectedReturnConsumesBusyAndEmptyDrafts() {
        let view = makeEditor(width: 360)
        view.setEditing(true, focusRequest: 1)
        var submissions = 0
        view.editor.onSubmit = {
            submissions += 1
            return false
        }
        for text in ["Busy draft", "", "   "] {
            view.setTextIfNeeded(text)
            view.editor.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
            view.editor.keyDown(with: NativeTextTestSupport.keyEvent())
            #expect(view.editor.string == text)
            #expect(view.editor.selectedRange().location == text.utf16.count)
        }
        #expect(submissions == 3)
    }

    @Test func shiftReturnInsertsNativeNewlineWithoutSubmitting() {
        let view = makeEditor(width: 360)
        let window = NativeTextTestSupport.window(containing: view)
        defer { window.contentView = nil }
        view.setEditing(true, focusRequest: 1)
        view.setTextIfNeeded("Line")
        view.editor.setSelectedRange(NSRange(location: 4, length: 0))
        var submissions = 0
        view.editor.onSubmit = {
            submissions += 1
            return true
        }
        view.editor.keyDown(with: NativeTextTestSupport.keyEvent(modifiers: .shift))
        #expect(view.editor.string == "Line\n")
        #expect(submissions == 0)

        // These selectors can also be sent explicitly by native key bindings.
        view.editor.insertLineBreak(nil)
        view.editor.insertNewlineIgnoringFieldEditor(nil)
        #expect(view.editor.string == "Line\n\u{2028}\n")
        #expect(submissions == 0)
    }

    @Test func markedTextReturnUsesNativeCompositionPathWithoutSubmitting() {
        let view = makeEditor(width: 360)
        let window = NativeTextTestSupport.window(containing: view)
        defer { window.contentView = nil }
        view.setEditing(true, focusRequest: 1)
        var submissions = 0
        view.editor.onSubmit = {
            submissions += 1
            return true
        }
        view.editor.setMarkedText("compose", selectedRange: NSRange(location: 7, length: 0),
                                  replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.editor.hasMarkedText())
        view.editor.keyDown(with: NativeTextTestSupport.keyEvent())
        #expect(submissions == 0)

        // Synthetic marked text has no real IME behind it. Compare with AppKit
        // rather than assuming the active input source's confirmation behavior.
        let native = NSTextView(frame: view.frame)
        native.isRichText = false
        window.contentView = native
        window.makeFirstResponder(native)
        native.setMarkedText("compose", selectedRange: NSRange(location: 7, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        native.keyDown(with: NativeTextTestSupport.keyEvent())
        #expect(view.editor.string == native.string)
        #expect(view.editor.hasMarkedText() == native.hasMarkedText())
    }

    @Test func submissionClearsUndoOnlyWhenAccepted() {
        let view = makeEditor(width: 360)
        let responder = DraftUndoResponder()
        responder.edits.groupsByEvent = false
        view.editor.nextResponder = responder
        view.setEditing(true, focusRequest: 1)
        view.setTextIfNeeded("Draft")
        view.editor.setSelectedRange(NSRange(location: 5, length: 0))
        responder.edits.beginUndoGrouping()
        view.editor.insertText(" addition", replacementRange: view.editor.selectedRange())
        view.editor.breakUndoCoalescing()
        responder.edits.endUndoGrouping()
        #expect(responder.edits.canUndo)

        view.editor.onSubmit = { false }
        view.editor.keyDown(with: NativeTextTestSupport.keyEvent())
        #expect(responder.edits.canUndo)
        #expect(view.editor.string == "Draft addition")

        responder.edits.beginUndoGrouping()
        view.editor.setSelectedRange(NSRange(location: 0, length: view.editor.string.utf16.count))
        view.editor.deleteBackward(nil)
        view.editor.breakUndoCoalescing()
        responder.edits.endUndoGrouping()
        view.editor.keyDown(with: NativeTextTestSupport.keyEvent())
        #expect(view.editor.string.isEmpty)
        #expect(responder.edits.canUndo)
        responder.edits.undo()
        #expect(view.editor.string == "Draft addition")
        #expect(responder.edits.canRedo)
        view.setEditing(false, focusRequest: 1)
        view.setEditing(true, focusRequest: 2)
        #expect(responder.edits.canUndo)

        view.editor.onSubmit = {
            #expect(responder.edits.canUndo)
            #expect(responder.edits.canRedo)
            // Model the owner accepting and clearing its draft during submit.
            view.setTextIfNeeded("")
            return true
        }
        view.editor.keyDown(with: NativeTextTestSupport.keyEvent())
        #expect(view.editor.string.isEmpty)
        #expect(!responder.edits.canUndo)
        #expect(!responder.edits.canRedo)

        responder.edits.beginUndoGrouping()
        view.editor.insertText("Next draft", replacementRange: view.editor.selectedRange())
        view.editor.breakUndoCoalescing()
        responder.edits.endUndoGrouping()
        responder.edits.undo()
        #expect(view.editor.string.isEmpty)
        #expect(!responder.edits.canUndo)
    }

    @Test func zeroWidthDoesNotPublishAnInvalidMeasurement() {
        let view = makeEditor(width: 0)
        #expect(view.refreshLayout() == nil)
        #expect(view.measuredContentHeight == nil)
        view.setFrameSize(NSSize(width: 300, height: DraftEditor.minimumHeight))
        #expect(view.refreshLayout() == DraftEditor.minimumHeight)
    }

    @Test func heightReportsAreDeferredAndOnlyPublishLatestMeasurement() async {
        let view = makeEditor(width: 300)
        var heights: [CGFloat] = []
        view.onHeightChange = { heights.append($0) }
        view.refreshLayout()
        view.setTextIfNeeded(Array(repeating: "Line", count: 20).joined(separator: "\n"))
        view.refreshLayout()
        #expect(heights.isEmpty)
        await drainMainQueue()
        #expect(heights == [DraftEditor.maximumHeight])

        // An intermediate pending shrink must not overwrite the current height.
        view.setTextIfNeeded("")
        view.refreshLayout()
        view.setTextIfNeeded(Array(repeating: "Line", count: 20).joined(separator: "\n"))
        view.refreshLayout()
        await drainMainQueue()
        #expect(heights == [DraftEditor.maximumHeight])

        view.setTextIfNeeded("")
        view.refreshLayout()
        await drainMainQueue()
        #expect(heights == [DraftEditor.maximumHeight, DraftEditor.minimumHeight])
    }

    @Test func queuedReportsRevalidateWidthAndCanBeCancelled() async {
        let view = makeEditor(width: 480)
        var heights: [CGFloat] = []
        view.onHeightChange = { heights.append($0) }
        view.setTextIfNeeded(Array(repeating: "A thought worth keeping", count: 8).joined(separator: " "))
        view.refreshLayout()
        // Change width without requesting a new measurement ourselves.
        view.setFrameSize(NSSize(width: 100, height: DraftEditor.minimumHeight))
        await drainMainQueue()
        await drainMainQueue()
        #expect(heights == [DraftEditor.maximumHeight])

        view.setTextIfNeeded("")
        view.refreshLayout()
        view.cancelHeightReport()
        await drainMainQueue()
        #expect(heights == [DraftEditor.maximumHeight])

        view.refreshLayout()
        view.setFrameSize(NSSize(width: 0, height: DraftEditor.minimumHeight))
        await drainMainQueue()
        #expect(heights == [DraftEditor.maximumHeight])
    }

    @Test func fontChangesRemeasureExistingTextAndReportNativeHeight() async throws {
        let view = makeEditor(width: 300)
        view.setTextIfNeeded("One\nTwo\nThree\nFour\n")
        var heights: [CGFloat] = []
        view.onHeightChange = { heights.append($0) }
        view.setFontSize(11)
        await drainMainQueue()
        let smallHeight = try #require(view.measuredContentHeight)
        #expect(smallHeight == NativeTextTestSupport.height(of: view.editor))

        view.setFontSize(24)
        await drainMainQueue()
        #expect(view.editor.font?.pointSize == 24)
        #expect((view.editor.typingAttributes[.font] as? NSFont)?.pointSize == 24)
        #expect(view.measuredContentHeight == NativeTextTestSupport.height(of: view.editor))
        #expect(try #require(view.measuredContentHeight) > smallHeight)
        #expect(view.editor.string == "One\nTwo\nThree\nFour\n")
        #expect(heights.last == min(DraftEditor.maximumHeight, NativeTextTestSupport.height(of: view.editor)))
    }

    @Test func equalUpdatesCollapseAndFontChangesPreserveNativeEditingContinuity() {
        let view = DraftEditorScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 140))
        let responder = DraftUndoResponder()
        responder.edits.groupsByEvent = false
        view.editor.nextResponder = responder
        view.setEditing(true, focusRequest: 1)
        let draft = Array(repeating: "A long draft line", count: 40).joined(separator: "\n")
        view.setTextIfNeeded(draft)
        view.editor.setSelectedRange(NSRange(location: draft.utf16.count, length: 0))
        responder.edits.beginUndoGrouping()
        view.editor.insertText(" addition", replacementRange: view.editor.selectedRange())
        view.editor.breakUndoCoalescing()
        responder.edits.endUndoGrouping()
        view.refreshLayout()
        let selection = NSRange(location: 4, length: 8)
        view.editor.setSelectedRange(selection)
        view.contentView.scroll(to: NSPoint(x: 0, y: 40))
        view.reflectScrolledClipView(view.contentView)

        view.setTextIfNeeded(view.editor.string)
        view.setEditing(false, focusRequest: 1)
        #expect(!view.editor.acceptsFirstResponder)
        #expect(view.editor.selectedRange() == selection)
        view.setEditing(true, focusRequest: 2)
        #expect(view.editor.acceptsFirstResponder)
        #expect(view.editor.selectedRange() == selection)
        view.setFontSize(24)
        #expect(view.editor.selectedRange() == selection)
        #expect(view.contentView.bounds.minY == 40)
        responder.edits.undo()
        #expect(view.editor.string == draft)
        responder.edits.redo()
        #expect(view.editor.string == draft + " addition")
        view.editor.setSelectedRange(NSRange(location: view.editor.string.utf16.count, length: 0))
        responder.edits.beginUndoGrouping()
        view.editor.insertNewline(nil)
        view.editor.breakUndoCoalescing()
        responder.edits.endUndoGrouping()
        #expect(view.editor.string == draft + " addition\n")
    }

    @Test func tabNavigatesToConversationWithoutEditingOrSubmitting() {
        let view = makeEditor(width: 360)
        view.setEditing(true, focusRequest: 1)
        view.setTextIfNeeded("Keep this draft")
        var requests = 0
        var submissions = 0
        view.editor.onFocusConversation = { requests += 1 }
        view.editor.onSubmit = { submissions += 1; return true }
        for modifiers: NSEvent.ModifierFlags in [[], .shift] {
            let previousRequests = requests
            view.editor.keyDown(with: NativeTextTestSupport.keyEvent(code: 48, modifiers: modifiers))
            #expect(requests > previousRequests)
        }
        #expect(submissions == 0)
        #expect(view.editor.string == "Keep this draft")
    }

    @Test func wheelIsIgnoredAndEscapeStillReachesPanelResponder() throws {
        let view = makeEditor(width: 300)
        view.setEditing(true, focusRequest: 1)
        view.setTextIfNeeded(Array(repeating: "Long draft", count: 40).joined(separator: "\n"))
        view.refreshLayout()
        view.editor.moveToBeginningOfDocument(nil)
        let origin = view.contentView.bounds.origin
        let cgEvent = try #require(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
            wheel1: -80, wheel2: 0, wheel3: 0
        ))
        let event = try #require(NSEvent(cgEvent: cgEvent))
        view.scrollWheel(with: event)
        view.editor.scrollWheel(with: event)
        #expect(view.contentView.bounds.origin == origin)
        let responder = DraftCancelResponder()
        view.nextResponder = responder
        view.editor.cancelOperation(nil)
        #expect(responder.cancellations == 1)
    }

    @Test func hostLayoutCannotShiftDraftTextAboveItsViewport() {
        let view = makeEditor(width: 360)
        view.setTextIfNeeded("Keep the first line visible")
        view.editor.setFrameOrigin(NSPoint(x: 0, y: -20))
        view.refreshLayout()
        #expect(view.editor.frame.origin == .zero)
    }

    private func makeEditor(width: CGFloat) -> DraftEditorScrollView {
        DraftEditorScrollView(frame: NSRect(x: 0, y: 0, width: width, height: DraftEditor.minimumHeight))
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@MainActor
private final class DraftCancelResponder: NSResponder {
    var cancellations = 0
    override func cancelOperation(_ sender: Any?) { cancellations += 1 }
}

@MainActor
private final class DraftUndoResponder: NSResponder {
    let edits = UndoManager()
    override var undoManager: UndoManager? { edits }
}
