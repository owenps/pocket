import AppKit
import PocketTestSupport
import Testing
@testable import Pocket

@MainActor
struct ConversationViewTests {
    @Test func turnsUseSpacingAndToneWithoutSenderLabels() throws {
        let view = makeTranscript()
        view.setConversation([
            ConversationMessage(role: .user, text: "Question"),
            ConversationMessage(role: .assistant, text: "Answer"),
        ], phase: .idle)
        #expect(view.transcript.string == "Question\n\nAnswer")
        let storage = try #require(view.transcript.textStorage)
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .secondaryLabelColor)
        #expect(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == NSFont.preferredFont(forTextStyle: .body))
        #expect(storage.attribute(.foregroundColor, at: 10, effectiveRange: nil) as? NSColor == .labelColor)
        #expect(storage.attribute(.font, at: 10, effectiveRange: nil) as? NSFont == NSFont.preferredFont(forTextStyle: .body))
    }

    @Test func thinkingIsOnlyTheLastEmptyAssistantAndStoppedHasAnHonestFallback() throws {
        let view = makeTranscript()
        view.setConversation([
            ConversationMessage(role: .assistant, text: ""),
            ConversationMessage(role: .user, text: "Next"),
            ConversationMessage(role: .assistant, text: ""),
        ], phase: .working)
        #expect(view.transcript.string == "Next\n\nthinking...")
        let storage = try #require(view.transcript.textStorage)
        #expect(storage.attribute(.foregroundColor, at: storage.length - 1, effectiveRange: nil) as? NSColor == .secondaryLabelColor)

        view.setConversation([ConversationMessage(role: .assistant, text: "", outcome: .stopped)], phase: .working)
        #expect(view.transcript.string == "Reply stopped.")
        view.setConversation([ConversationMessage(role: .assistant, text: "Partial answer", outcome: .stopped)], phase: .idle)
        #expect(view.transcript.string == "Partial answer\nStopped.")
        view.setConversation([ConversationMessage(role: .assistant, text: "Already answering")], phase: .working)
        #expect(view.transcript.string == "Already answering")
        view.setConversation([ConversationMessage(role: .assistant, text: "", outcome: .completed)], phase: .working)
        #expect(view.transcript.string.isEmpty)
        for phase: ReplyPhase in [.idle, .streaming] {
            view.setConversation([ConversationMessage(role: .assistant, text: "")], phase: phase)
            #expect(view.transcript.string == (phase == .idle ? "" : "thinking..."))
        }
        view.setConversation([ConversationMessage(role: .user, text: "")], phase: .working)
        #expect(view.transcript.string.isEmpty)
        view.setConversation([], phase: .working)
        #expect(view.transcript.string.isEmpty)
    }

    @Test(arguments: ["", "Partial answer"])
    func failedRepliesShowTheFailureWithoutDiscardingPartialText(partial: String) {
        let view = makeTranscript()
        view.setConversation([
            ConversationMessage(role: .assistant, text: partial, outcome: .failed("Connection lost")),
        ], phase: .idle)
        let expected = partial.isEmpty ? "Reply failed: Connection lost" : "\(partial)\nReply failed: Connection lost"
        #expect(view.transcript.string == expected)
    }

    @Test func transcriptIsReadOnlySelectableAndAcceptsFirstClick() {
        let view = makeTranscript()
        #expect(!view.transcript.isEditable)
        #expect(view.transcript.isSelectable)
        #expect(view.acceptsFirstMouse(for: nil))
        #expect(view.transcript.acceptsFirstMouse(for: nil))
    }

    @Test func longDocumentUsesActualTextKitHeightAndTracksViewportWidth() throws {
        let view = makeTranscript(width: 420)
        view.setConversation(longConversation(), phase: .streaming)
        let wideHeight = view.transcript.frame.height
        #expect(wideHeight > 180)
        #expect(view.frame.height == 180)
        #expect(wideHeight == NativeTextTestSupport.height(of: view.transcript))
        view.setFrameSize(NSSize(width: 150, height: 180))
        view.refreshLayout()
        #expect(view.transcript.frame.height > wideHeight)
        #expect(view.transcript.frame.height == NativeTextTestSupport.height(of: view.transcript))
        #expect(view.transcript.frame.width == view.contentView.bounds.width)
        #expect(view.transcript.textContainer?.containerSize.width == view.transcript.frame.width)
        #expect(view.frame.height == 180)
        view.setConversation([ConversationMessage(role: .user, text: "Short")], phase: .idle)
        #expect(view.transcript.frame.height == view.contentView.bounds.height)
    }

    @Test func reportsNaturalHeightRatherThanViewportHeightOrParentCap() async {
        let view = makeTranscript(height: 180)
        defer { view.cleanUp() }
        var heights: [CGFloat] = []
        view.configure(animateThinking: false, onContentHeightChanged: { heights.append($0) })
        view.setConversation([ConversationMessage(role: .assistant, text: "Short reply")], phase: .idle)
        #expect(heights.isEmpty)
        await drainMainQueue()
        #expect(heights == [NativeTextTestSupport.height(of: view.transcript)])
        #expect(heights.first.map { $0 > 0 && $0 < 112 } == true)
        #expect(view.transcript.frame.height == 180)

        view.setConversation(longConversation(), phase: .streaming)
        await drainMainQueue()
        #expect(heights.last == NativeTextTestSupport.height(of: view.transcript))
        #expect(heights.last.map { $0 > 112 } == true)
        #expect(view.frame.height == 180)
    }

    @Test func zeroHeightMountReportsOnceWidthExistsAndCanStartParentGrowth() async {
        let view = ConversationScrollView(frame: .zero)
        defer { view.cleanUp() }
        var heights: [CGFloat] = []
        view.configure(animateThinking: false, onContentHeightChanged: { height in
            heights.append(height)
            view.setFrameSize(NSSize(width: 300, height: min(112, height)))
        })
        view.setConversation([ConversationMessage(role: .assistant, text: "Ready")], phase: .idle)
        await drainMainQueue()
        #expect(heights.isEmpty)
        view.setFrameSize(NSSize(width: 300, height: 0))
        #expect(view.frame.height == 0)
        #expect(heights.isEmpty)
        await drainMainQueue()
        #expect(heights == [NativeTextTestSupport.height(of: view.transcript)])
        #expect(view.frame.height > 0)
        #expect(view.frame.height == heights.first)
        #expect(isAtBottom(view))
    }

    @Test func heightReportsCoalesceLatestAndIgnoreVerticalViewportAnimation() async {
        let view = makeTranscript(width: 420)
        defer { view.cleanUp() }
        var heights: [CGFloat] = []
        view.configure(animateThinking: false, onContentHeightChanged: { heights.append($0) })
        view.setConversation([ConversationMessage(role: .assistant, text: "First")], phase: .streaming)
        let messages = longConversation()
        view.setConversation(messages, phase: .streaming)
        view.setFrameSize(NSSize(width: 300, height: 80))
        #expect(heights.isEmpty)
        let latest = NativeTextTestSupport.height(of: view.transcript)
        await drainMainQueue()
        #expect(heights == [latest])

        for height: CGFloat in [0, 1, 40, 112, 180, 90] {
            view.setFrameSize(NSSize(width: 300, height: height))
            view.setConversation(messages, phase: .streaming)
            view.refreshLayout()
            await drainMainQueue()
        }
        #expect(heights == [latest])
        view.setFrameSize(NSSize(width: 150, height: 90))
        await drainMainQueue()
        #expect(heights.count == 2)
        #expect(heights.last == NativeTextTestSupport.height(of: view.transcript))
        #expect(heights.last.map { $0 > latest } == true)

        // A queued change which returns to the last reported height is silent.
        view.setFrameSize(NSSize(width: 420, height: 90))
        view.setFrameSize(NSSize(width: 150, height: 90))
        await drainMainQueue()
        #expect(heights.count == 2)
    }

    @Test func cleanupCancelsDeferredHeightReports() async {
        let view = makeTranscript()
        var heights: [CGFloat] = []
        view.configure(animateThinking: false, onContentHeightChanged: { heights.append($0) })
        view.setConversation(longConversation(), phase: .idle)
        view.cleanUp()
        view.setFrameSize(NSSize(width: 150, height: 112))
        view.refreshLayout()
        await drainMainQueue()
        #expect(heights.isEmpty)
    }

    @Test func viewportResizingFollowsBottomButPreservesAnOlderReadingPosition() {
        let view = makeTranscript(height: 40)
        defer { view.cleanUp() }
        view.setConversation(longConversation(), phase: .streaming)
        #expect(isAtBottom(view))
        for height: CGFloat in [80, 112, 60, 1, 0, 40, 180, 112] {
            view.setFrameSize(NSSize(width: 300, height: height))
            if height > 0 { #expect(isAtBottom(view)) }
        }
        let selection = NSRange(location: 20, length: 9)
        view.transcript.setSelectedRange(selection)
        view.contentView.scroll(to: NSPoint(x: 0, y: 45))
        view.reflectScrolledClipView(view.contentView)
        let origin = view.contentView.bounds.origin
        for height: CGFloat in [180, 40, 112, 1, 0, 80] {
            view.setFrameSize(NSSize(width: 300, height: height))
            #expect(view.contentView.bounds.origin == origin)
            #expect(view.transcript.selectedRange() == selection)
            #expect(!isAtBottom(view))
        }
    }

    @Test func outputFollowsBottomButPreservesAnOlderReadingPositionAndSelection() {
        let view = makeTranscript()
        var messages = longConversation()
        view.setConversation(messages, phase: .streaming)
        #expect(isAtBottom(view))
        let oldBottom = view.contentView.bounds.minY
        messages[0].text += "\nMore output\nMore output"
        view.setConversation(messages, phase: .streaming)
        #expect(isAtBottom(view))
        #expect(view.contentView.bounds.minY > oldBottom)

        view.contentView.scroll(to: NSPoint(x: 0, y: 45))
        view.reflectScrolledClipView(view.contentView)
        let origin = view.contentView.bounds.origin
        let selection = NSRange(location: 20, length: 9)
        view.transcript.setSelectedRange(selection)
        messages[0].text += "\nStill more output"
        view.setConversation(messages, phase: .streaming)
        #expect(view.contentView.bounds.origin == origin)
        #expect(view.transcript.selectedRange() == selection)
        #expect(!isAtBottom(view))
    }

    @Test func unchangedRenderingDoesNotEditStorageOrDisturbSelectionAndScroll() {
        let view = makeTranscript()
        let messages = longConversation()
        view.setConversation(messages, phase: .streaming)
        view.contentView.scroll(to: NSPoint(x: 0, y: 60))
        let origin = view.contentView.bounds.origin
        let selection = NSRange(location: 12, length: 15)
        view.transcript.setSelectedRange(selection)
        let observer = TranscriptStorageObserver()
        view.transcript.textStorage?.delegate = observer
        view.setConversation(messages, phase: .idle)
        view.setExpanded(false, focusRequest: 1)
        #expect(observer.edits == 0)
        #expect(view.transcript.selectedRange() == selection)
        #expect(view.contentView.bounds.origin == origin)
        #expect(!view.transcript.acceptsFirstResponder)
        view.transcript.textStorage?.delegate = nil
    }

    @Test func selectionIsClampedWhenDocumentShrinks() {
        let view = makeTranscript()
        view.setConversation(longConversation(), phase: .idle)
        view.transcript.setSelectedRange(NSRange(location: view.transcript.string.utf16.count - 4, length: 4))
        view.setConversation([], phase: .idle)
        #expect(view.transcript.selectedRange() == NSRange(location: 0, length: 0))
        #expect(view.contentView.bounds.minY == 0)
    }

    @Test func outputBeforeInitialLayoutStillFollowsBottomOnceViewportExists() {
        let view = ConversationScrollView(frame: .zero)
        view.setConversation(longConversation(), phase: .working)
        view.setFrameSize(NSSize(width: 300, height: 180))
        view.refreshLayout()
        #expect(isAtBottom(view))
        #expect(view.contentView.bounds.minY > 0)
    }

    @Test func wheelIsIgnoredButNativeDocumentAndPageCommandsStillScroll() throws {
        let view = makeTranscript()
        view.setExpanded(true, focusRequest: 1)
        view.setConversation(longConversation(), phase: .idle)
        view.transcript.moveToBeginningOfDocument(nil)
        #expect(view.contentView.bounds.minY == 0)
        // An arrow move inside the viewport need not scroll. Continue native
        // navigation until the caret actually travels beyond the visible lines.
        var previousSelection = NSRange(location: NSNotFound, length: 0)
        while view.contentView.bounds.minY == 0, view.transcript.selectedRange() != previousSelection {
            previousSelection = view.transcript.selectedRange()
            view.transcript.moveDown(nil)
        }
        #expect(view.contentView.bounds.minY > 0)
        view.transcript.pageDown(nil)
        #expect(view.contentView.bounds.minY > 0)
        view.transcript.moveToEndOfDocument(nil)
        #expect(isAtBottom(view))
        view.transcript.pageUp(nil)
        #expect(!isAtBottom(view))
        let origin = view.contentView.bounds.origin
        let cgEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -80, wheel2: 0, wheel3: 0))
        let event = try #require(NSEvent(cgEvent: cgEvent))
        view.scrollWheel(with: event)
        view.transcript.scrollWheel(with: event)
        #expect(view.contentView.bounds.origin == origin)
        #expect(view.transcript.responds(to: #selector(NSText.copy(_:))))
        view.transcript.moveToBeginningOfDocument(nil)
        #expect(view.contentView.bounds.minY == 0)
    }

    @Test func tabShiftTabAndReturnRouteToComposerWithoutChangingText() {
        let view = makeTranscript()
        view.setConversation([ConversationMessage(role: .user, text: "Keep me")], phase: .idle)
        var requestedComposer = false
        view.transcript.onFocusComposer = { requestedComposer = true }
        for (keyCode, modifiers): (UInt16, NSEvent.ModifierFlags) in [(48, []), (48, .shift), (36, []), (76, [])] {
            requestedComposer = false
            view.transcript.keyDown(with: NativeTextTestSupport.keyEvent(code: keyCode, modifiers: modifiers))
            #expect(requestedComposer)
        }
        requestedComposer = false
        view.transcript.insertTab(nil)
        #expect(requestedComposer)
        requestedComposer = false
        view.transcript.insertBacktab(nil)
        #expect(requestedComposer)
        requestedComposer = false
        view.transcript.insertNewline(nil)
        #expect(requestedComposer)
        #expect(view.transcript.string == "Keep me")
    }

    @Test func escapeBubblesThroughNativeResponderChain() {
        let view = makeTranscript()
        let responder = TranscriptCancelResponder()
        view.nextResponder = responder
        var composerRequests = 0
        view.transcript.onFocusComposer = { composerRequests += 1 }
        view.transcript.cancelOperation(nil)
        #expect(responder.cancellations == 1)
        #expect(composerRequests == 0)
    }

    @Test func focusIsDeferredUntilAttachmentAndOnlyNewExpandedRequestsAreFulfilled() {
        let view = makeTranscript()
        view.setExpanded(true, focusRequest: 1)
        #expect(view.window == nil)
        #expect(view.transcript.acceptsFirstResponder)
        let root = NSView(frame: view.frame)
        let composer = NSTextView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        root.addSubview(composer)
        root.addSubview(view)
        let window = NativeTextTestSupport.window(containing: root, shown: true)
        defer { window.contentView = nil }
        #expect(window.firstResponder === view.transcript)
        #expect(window.makeFirstResponder(composer))
        view.setExpanded(true, focusRequest: 1)
        #expect(window.firstResponder === composer)
        view.setExpanded(false, focusRequest: 2)
        #expect(window.firstResponder === composer)
        #expect(!view.transcript.acceptsFirstResponder)
        view.setConversation([ConversationMessage(role: .assistant, text: "Updates while collapsed")], phase: .streaming)
        #expect(view.transcript.string == "Updates while collapsed")
        #expect(window.firstResponder === composer)
        view.setExpanded(true, focusRequest: 2)
        #expect(window.firstResponder === view.transcript)
        #expect(window.makeFirstResponder(composer))
        view.setExpanded(false, focusRequest: 0)
        view.setExpanded(true, focusRequest: 0)
        #expect(window.firstResponder === composer)
        view.setExpanded(true, focusRequest: 1)
        #expect(window.firstResponder === view.transcript)
    }

    @Test func mountingConversationDoesNotStealComposerFocus() {
        let view = makeTranscript()
        view.setExpanded(true, focusRequest: 0)
        let root = NSView(frame: view.frame)
        let composer = NSTextView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        root.addSubview(composer)
        let window = NativeTextTestSupport.window(containing: root, shown: true)
        defer { window.contentView = nil }
        #expect(window.makeFirstResponder(composer))
        root.addSubview(view)
        view.setConversation([ConversationMessage(role: .assistant, text: "")], phase: .working)
        view.setExpanded(true, focusRequest: 0)
        #expect(window.firstResponder === composer)
        view.setExpanded(true, focusRequest: 1)
        #expect(window.firstResponder === view.transcript)
    }

    @Test func hostLayoutCannotLeaveTheDocumentShiftedAboveItsViewport() {
        let view = makeTranscript()
        view.setConversation([ConversationMessage(role: .user, text: "First line stays visible")], phase: .idle)
        view.transcript.setFrameOrigin(NSPoint(x: 0, y: -20))
        view.refreshLayout()
        #expect(view.transcript.frame.origin == .zero)
        #expect(view.contentView.bounds.origin == .zero)
    }

    @Test func newUserTurnFollowsEvenWhenReadingEarlierOutputInSmallViewport() {
        let view = makeTranscript(height: 112)
        var messages = longConversation()
        view.setConversation(messages, phase: .streaming)
        view.transcript.moveToBeginningOfDocument(nil)
        let selection = NSRange(location: 5, length: 7)
        view.transcript.setSelectedRange(selection)
        messages[0].text += "\nStreamed while reading"
        view.setConversation(messages, phase: .streaming)
        #expect(view.contentView.bounds.minY == 0)
        #expect(view.transcript.selectedRange() == selection)
        messages.append(ConversationMessage(role: .user, text: "Another question"))
        messages.append(ConversationMessage(role: .assistant, text: ""))
        view.setConversation(messages, phase: .working)
        #expect(isAtBottom(view))
        #expect(view.transcript.string.hasSuffix("Another question\n\nthinking..."))
        #expect(view.transcript.selectedRange() == selection)
        messages[messages.count - 1].text = "The next answer"
        view.setConversation(messages, phase: .streaming)
        #expect(isAtBottom(view))
        view.transcript.pageUp(nil)
        #expect(!isAtBottom(view))
        let origin = view.contentView.bounds.origin
        messages[messages.count - 1].text += "\nMore answer"
        view.setConversation(messages, phase: .streaming)
        #expect(view.contentView.bounds.origin == origin)
        view.transcript.moveToEndOfDocument(nil)
        #expect(isAtBottom(view))
        view.transcript.moveToBeginningOfDocument(nil)
        #expect(view.contentView.bounds.minY == 0)
        #expect(view.frame.height == 112)
    }

    @Test func readReceiptWaitsForIdleAndNativeKeyboardScrollToLatestReply() async {
        let view = makeTranscript(height: 112)
        let window = attach(view, shown: true)
        defer { view.cleanUp(); window.contentView = nil }
        var receipts: [UUID] = []
        view.configure(animateThinking: false, onReplyViewed: { receipts.append($0) })
        var messages = longConversation()
        view.setConversation(messages, phase: .streaming)
        view.setExpanded(true, focusRequest: 0)
        await drainMainQueue()
        #expect(receipts.isEmpty)
        view.transcript.moveToBeginningOfDocument(nil)
        view.setConversation(messages, phase: .idle)
        await drainMainQueue()
        #expect(receipts.isEmpty)
        view.transcript.pageDown(nil)
        await drainMainQueue()
        #expect(receipts.isEmpty)
        view.transcript.moveToEndOfDocument(nil)
        #expect(receipts.isEmpty) // Never synchronously from a clip/layout callback.
        view.transcript.moveToBeginningOfDocument(nil)
        await drainMainQueue()
        #expect(receipts.isEmpty)
        view.transcript.moveToEndOfDocument(nil)
        await drainMainQueue()
        #expect(receipts == [messages[0].id])
        view.refreshLayout()
        view.transcript.pageUp(nil)
        view.transcript.moveToEndOfDocument(nil)
        await drainMainQueue()
        #expect(receipts == [messages[0].id])

        messages.append(ConversationMessage(role: .user, text: "Next"))
        let empty = ConversationMessage(role: .assistant, text: "")
        messages.append(empty)
        view.setConversation(messages, phase: .working)
        await drainMainQueue()
        #expect(receipts == [messages[0].id])
        view.setConversation(messages, phase: .idle)
        await drainMainQueue()
        #expect(receipts == [messages[0].id])
        messages[messages.count - 1].outcome = .stopped
        view.setConversation(messages, phase: .idle)
        await drainMainQueue()
        #expect(receipts == [messages[0].id, empty.id])

        let failed = ConversationMessage(role: .assistant, text: "", outcome: .failed("Connection lost"))
        view.setConversation([failed], phase: .idle)
        await drainMainQueue()
        #expect(receipts == [messages[0].id, empty.id, failed.id])
    }

    @Test func tinyGrowingViewportWaitsUntilEntireFinalLineIsVisibleForReceipt() async throws {
        let view = makeTranscript(height: 112)
        let window = attach(view, shown: true)
        defer { view.cleanUp(); window.contentView = nil }
        var receipts: [UUID] = []
        view.configure(animateThinking: false, onReplyViewed: { receipts.append($0) })
        view.setFrameSize(NSSize(width: 300, height: 1))
        let reply = ConversationMessage(role: .assistant, text: "An answer\nFinal line")
        view.setConversation([reply], phase: .idle)
        view.setExpanded(true, focusRequest: 0)
        await drainMainQueue()
        #expect(receipts.isEmpty)
        #expect(isAtBottom(view))

        let manager = try #require(view.transcript.layoutManager)
        let container = try #require(view.transcript.textContainer)
        let line = manager.lineFragmentRect(forGlyphAt: manager.numberOfGlyphs - 1, effectiveRange: nil)
        let partialHeight = ceil(line.height / 2) + view.transcript.textContainerInset.height
        view.setFrameSize(NSSize(width: 300, height: partialHeight))
        let glyph = manager.boundingRect(forGlyphRange: NSRange(location: manager.numberOfGlyphs - 1, length: 1),
                                        in: container)
            .offsetBy(dx: view.transcript.textContainerOrigin.x, dy: view.transcript.textContainerOrigin.y)
        #expect(view.transcript.visibleRect.intersects(glyph))
        #expect(isAtBottom(view))
        await drainMainQueue()
        #expect(receipts.isEmpty)

        view.setFrameSize(NSSize(width: 300, height: ceil(line.height) + view.transcript.textContainerInset.height * 2))
        #expect(receipts.isEmpty)
        await drainMainQueue()
        #expect(receipts == [reply.id])
    }

    @Test func hiddenUnshownAndUnrevealedTranscriptsNeitherAcknowledgeNorFocus() async {
        let view = makeTranscript(height: 112)
        let reply = ConversationMessage(role: .assistant, text: "Ready")
        var receipts: [UUID] = []
        view.configure(animateThinking: false, onReplyViewed: { receipts.append($0) })
        view.setConversation([reply], phase: .idle)
        view.setExpanded(true, focusRequest: 1)
        await drainMainQueue()
        #expect(receipts.isEmpty)
        let window = attach(view, shown: false)
        defer { view.cleanUp(); window.contentView = nil }
        #expect(window.firstResponder !== view.transcript)
        let composer = NSTextView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        window.contentView?.addSubview(composer)
        #expect(window.makeFirstResponder(composer))
        view.setExpanded(true, focusRequest: 1)
        await drainMainQueue()
        #expect(window.firstResponder === composer)
        #expect(receipts.isEmpty)

        view.setExpanded(false, focusRequest: 1) // Opening/not fully revealed.
        window.shown = true
        view.refreshLayout()
        await drainMainQueue()
        #expect(window.firstResponder === composer)
        #expect(receipts.isEmpty)
        view.isHidden = true
        view.setExpanded(true, focusRequest: 1)
        await drainMainQueue()
        #expect(window.firstResponder === composer)
        #expect(receipts.isEmpty)
        view.isHidden = false
        await drainMainQueue()
        #expect(window.firstResponder === view.transcript)
        #expect(receipts == [reply.id])
    }

    @Test func deferredReceiptsRecheckVisibilityPhaseIdentityAndCleanup() async {
        let view = makeTranscript(height: 112)
        let window = attach(view, shown: true)
        defer { view.cleanUp(); window.contentView = nil }
        var receipts: [UUID] = []
        view.configure(animateThinking: false, onReplyViewed: { receipts.append($0) })
        view.setExpanded(true, focusRequest: 0)
        let stale = ConversationMessage(role: .assistant, text: "Old")
        view.setConversation([stale], phase: .idle)
        view.setExpanded(false, focusRequest: 0)
        await drainMainQueue()
        #expect(receipts.isEmpty)
        view.setExpanded(true, focusRequest: 0)
        window.shown = false
        await drainMainQueue()
        #expect(receipts.isEmpty)
        window.shown = true
        view.refreshLayout()
        view.setConversation([stale], phase: .streaming)
        await drainMainQueue()
        #expect(receipts.isEmpty)
        view.setConversation([stale], phase: .idle)
        let latest = ConversationMessage(role: .assistant, text: "Current")
        view.setConversation([latest], phase: .idle)
        await drainMainQueue()
        #expect(receipts == [latest.id])
        let unmounted = ConversationMessage(role: .assistant, text: "Unmounted")
        view.setConversation([unmounted], phase: .idle)
        view.removeFromSuperview()
        await drainMainQueue()
        #expect(receipts == [latest.id])
        window.contentView?.addSubview(view)
        view.cleanUp()
        await drainMainQueue()
        #expect(receipts == [latest.id])
        #expect(view.transcript.onFocusComposer == nil)
    }

    @Test func fontChangesRemeasureAndPreserveSelectionAndScrolling() async throws {
        let view = makeTranscript(height: 80)
        defer { view.cleanUp() }
        let messages = [ConversationMessage(role: .assistant, text:
            Array(repeating: "A response worth reading carefully", count: 50).joined(separator: " "), outcome: .stopped)]
        var heights: [CGFloat] = []
        view.configure(animateThinking: false, onContentHeightChanged: { heights.append($0) })
        view.setConversation(messages, phase: .idle, fontSize: 11)
        await drainMainQueue()
        let smallHeight = NativeTextTestSupport.height(of: view.transcript)
        #expect(heights.last == smallHeight)
        #expect(isAtBottom(view))
        let selection = NSRange(location: 10, length: 20)
        view.transcript.setSelectedRange(selection)
        let text = view.transcript.string

        view.setConversation(messages, phase: .idle, fontSize: 24)
        await drainMainQueue()
        #expect(NativeTextTestSupport.height(of: view.transcript) > smallHeight)
        #expect(heights.last == NativeTextTestSupport.height(of: view.transcript))
        #expect(isAtBottom(view))
        #expect(view.transcript.selectedRange() == selection)
        #expect(view.transcript.string == text)
        let storage = try #require(view.transcript.textStorage)
        #expect((storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 24)
        let statusFont = try #require(storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as? NSFont)
        #expect(statusFont.pointSize > NSFont.smallSystemFontSize)
        #expect(statusFont.pointSize < 24)

        view.contentView.scroll(to: NSPoint(x: 0, y: 45))
        view.reflectScrolledClipView(view.contentView)
        for fontSize in [18.0, 24.0] {
            view.setConversation(messages, phase: .idle, fontSize: fontSize)
            #expect(view.contentView.bounds.minY == 45)
            #expect(view.transcript.selectedRange() == selection)
            #expect(view.transcript.frame.height == NativeTextTestSupport.height(of: view.transcript))
        }
    }

    private func attach(_ view: ConversationScrollView, shown: Bool) -> OffscreenTestWindow {
        let root = NSView(frame: view.frame)
        root.addSubview(view)
        return NativeTextTestSupport.window(containing: root, shown: shown)
    }

    private func drainMainQueue() async {
        // A stale deferred candidate may enqueue a fresh eligibility check.
        for _ in 0..<2 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    @Test func receiptsRequireForegroundAndUnoccludedPresentation() async {
        let view = makeTranscript(height: 112)
        let window = NativeTextTestSupport.window(containing: view, shown: true)
        window.key = false
        defer { view.cleanUp(); window.contentView = nil }
        let reply = ConversationMessage(role: .assistant, text: "An unread reply")
        var receipts: [UUID] = []
        view.configure(animateThinking: false, onReplyViewed: { receipts.append($0) })
        view.setConversation([reply], phase: .idle)
        view.setExpanded(true, focusRequest: 0)
        await drainMainQueue()
        #expect(receipts.isEmpty)
        window.key = true
        window.exposed = false
        view.setExpanded(true, focusRequest: 0)
        await drainMainQueue()
        #expect(receipts.isEmpty)
        window.exposed = true
        view.setExpanded(true, focusRequest: 0)
        await drainMainQueue()
        #expect(receipts == [reply.id])
    }

    private func makeTranscript(width: CGFloat = 300, height: CGFloat = 180) -> ConversationScrollView {
        let view = ConversationScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.configure(animateThinking: false)
        return view
    }

    private func longConversation() -> [ConversationMessage] {
        [ConversationMessage(role: .assistant, text: Array(repeating: "A longer line of native transcript text that wraps naturally.", count: 40).joined(separator: "\n"))]
    }

    private func isAtBottom(_ view: ConversationScrollView) -> Bool {
        view.contentView.bounds.maxY >= view.transcript.frame.maxY - 2
    }

}

private final class TranscriptStorageObserver: NSObject, NSTextStorageDelegate {
    var edits = 0
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        edits += 1
    }
}

@MainActor
private final class TranscriptCancelResponder: NSResponder {
    var cancellations = 0
    override func cancelOperation(_ sender: Any?) { cancellations += 1 }
}
