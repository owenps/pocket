import AppKit
import SwiftUI

/// A persistent native editor; its parent owns the capped viewport height.
struct DraftEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditing: Bool
    var focusRequest: Int
    var onHeightChange: (CGFloat) -> Void
    /// Return true only when the owner accepts the draft.
    var onSubmit: (() -> Bool)? = nil
    var onFocusConversation: (() -> Void)? = nil
    var onMoveCommandSelection: ((Int) -> Bool)? = nil
    var onCompleteCommand: (() -> String?)? = nil
    var onDismissCommands: (() -> Bool)? = nil
    var fontSize: Double = Double(NSFont.preferredFont(forTextStyle: .body).pointSize)
    var userName = ""

    static let minimumHeight = singleLineHeight(fontSize: Double(NSFont.preferredFont(forTextStyle: .body).pointSize))
    static let maximumHeight = IslandGeometry.maximumEditorHeight

    static func singleLineHeight(fontSize: Double) -> CGFloat {
        let body = NSFont.preferredFont(forTextStyle: .body)
        let font = NSFont(descriptor: body.fontDescriptor, size: fontSize) ?? body
        return ceil(NSLayoutManager().defaultLineHeight(for: font) + 4)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> DraftEditorScrollView {
        let view = DraftEditorScrollView(frame: .zero)
        view.editor.delegate = context.coordinator
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DraftEditorScrollView, context: Context) {
        context.coordinator.text = $text
        view.onHeightChange = onHeightChange
        view.editor.onSubmit = onSubmit
        view.editor.onFocusConversation = onFocusConversation
        view.editor.onMoveCommandSelection = onMoveCommandSelection
        view.editor.onCompleteCommand = onCompleteCommand
        view.editor.onDismissCommands = onDismissCommands
        view.editor.userName = userName
        view.setTextIfNeeded(text)
        view.setFontSize(fontSize)
        view.setEditing(isEditing, focusRequest: focusRequest)
        view.refreshLayout()
    }

    static func dismantleNSView(_ view: DraftEditorScrollView, coordinator: Coordinator) {
        view.editor.delegate = nil
        view.editor.onSubmit = nil
        view.editor.onFocusConversation = nil
        view.editor.onMoveCommandSelection = nil
        view.editor.onCompleteCommand = nil
        view.editor.onDismissCommands = nil
        view.onHeightChange = nil
        view.cancelHeightReport()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            if text.wrappedValue != editor.string {
                text.wrappedValue = editor.string
            }
            (editor.enclosingScrollView as? DraftEditorScrollView)?.refreshLayout()
        }
    }
}

/// TextKit 1 provides both rendering and measurement, including the empty line
/// after a trailing Return. No secondary text storage or estimated line counts.
final class DraftEditorScrollView: NSScrollView {
    let editor: DraftTextView
    var onHeightChange: ((CGFloat) -> Void)?
    private(set) var measuredContentHeight: CGFloat?

    private let draftClipView = DraftClipView()
    private var isMeasuring = false
    private var requestedFocus: Int?
    private var fulfilledFocus: Int?
    private var heightRevision = 0
    private var pendingHeight: CGFloat?
    private var reportedHeight: CGFloat?

    override init(frame frameRect: NSRect) {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        editor = DraftTextView(frame: .zero, textContainer: container)
        super.init(frame: frameRect)

        contentView = draftClipView
        draftClipView.drawsBackground = false
        borderType = .noBorder
        drawsBackground = false
        focusRingType = .none
        hasHorizontalScroller = false
        hasVerticalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        horizontalScrollElasticity = .none

        editor.isRichText = false
        editor.importsGraphics = false
        editor.usesFontPanel = false
        editor.allowsUndo = true
        editor.isFieldEditor = false
        editor.drawsBackground = false
        editor.focusRingType = .none
        editor.font = NSFont.preferredFont(forTextStyle: .body)
        editor.textColor = .labelColor
        editor.insertionPointColor = .labelColor
        editor.textContainerInset = NSSize(width: 0, height: 2)
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]
        editor.setAccessibilityLabel("Message draft")
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        documentView = editor
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func scrollWheel(with event: NSEvent) {}

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if documentView === editor { refreshLayout() }
    }

    override func layout() {
        super.layout()
        refreshLayout()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        fulfillFocusRequest()
    }

    func setTextIfNeeded(_ text: String) {
        // Even assigning an identical string destroys native selection/undo state.
        guard editor.string != text else { return }
        editor.string = text
    }

    func setFontSize(_ size: Double) {
        guard size.isFinite, size > 0, editor.font?.pointSize != CGFloat(size),
              let font = NSFont(descriptor: NSFont.preferredFont(forTextStyle: .body).fontDescriptor,
                                size: CGFloat(size)) else { return }
        let selections = editor.selectedRanges
        let origin = contentView.bounds.origin
        // Restyle in place: replacing the string would discard native undo.
        editor.font = font
        editor.typingAttributes[.font] = font
        editor.selectedRanges = selections
        editor.needsDisplay = true
        refreshLayout()
        contentView.scroll(to: NSPoint(x: 0, y: min(origin.y, max(0, editor.frame.height - contentView.bounds.height))))
        reflectScrolledClipView(contentView)
    }

    func setEditing(_ isEditing: Bool, focusRequest: Int) {
        if isEditing && !editor.permitsFocus {
            editor.rotatePlaceholder()
        }
        editor.permitsFocus = isEditing
        editor.isEditable = isEditing
        requestedFocus = focusRequest
        // Collapse releases focus at the panel level, not by resetting this view.
        fulfillFocusRequest()
    }

    private func fulfillFocusRequest() {
        guard editor.permitsFocus, let requestedFocus,
              requestedFocus != fulfilledFocus, let window else { return }
        if window.makeFirstResponder(editor) {
            fulfilledFocus = requestedFocus
        }
    }

    /// Also callable without a window, for deterministic native-layout tests.
    @discardableResult
    func refreshLayout() -> CGFloat? {
        guard !isMeasuring else { return measuredContentHeight.map(Self.viewportHeight) }
        isMeasuring = true
        defer { isMeasuring = false }

        // Tile first: measurement uses the actual clip width, never the SwiftUI
        // proposal or a cached width from before scroller/layout changes.
        tile()
        let width = contentView.bounds.width
        guard width.isFinite, width > 0,
              let container = editor.textContainer, let manager = editor.layoutManager else {
            measuredContentHeight = nil
            cancelHeightReport()
            return nil
        }
        editor.setFrameSize(NSSize(width: width, height: max(editor.frame.height, contentSize.height)))
        manager.ensureLayout(for: container)
        var bottom = manager.usedRect(for: container).maxY
        if manager.extraLineFragmentTextContainer === container {
            bottom = max(bottom, manager.extraLineFragmentRect.maxY)
        }
        let naturalHeight = ceil(bottom + editor.textContainerInset.height * 2)
        guard naturalHeight.isFinite else {
            measuredContentHeight = nil
            cancelHeightReport()
            return nil
        }
        measuredContentHeight = naturalHeight
        draftClipView.permitsVerticalScrolling = naturalHeight > DraftEditor.maximumHeight
        editor.setFrameSize(NSSize(width: width, height: max(naturalHeight, contentSize.height)))
        editor.setFrameOrigin(.zero)
        let bounds = contentView.constrainBoundsRect(contentView.bounds)
        contentView.scroll(to: bounds.origin)
        reflectScrolledClipView(contentView)
        let height = Self.viewportHeight(naturalHeight)
        queueHeightReport(height)
        return height
    }

    private static func viewportHeight(_ contentHeight: CGFloat) -> CGFloat {
        IslandGeometry.editorViewportHeight(contentHeight)
    }

    func cancelHeightReport() {
        heightRevision &+= 1
        pendingHeight = nil
    }

    private func queueHeightReport(_ height: CGFloat) {
        guard pendingHeight != height else { return }
        cancelHeightReport()
        guard reportedHeight != height else { return }
        pendingHeight = height
        let revision = heightRevision
        DispatchQueue.main.async { [weak self] in
            guard let self, self.heightRevision == revision else { return }
            // Width/text may have changed since layout, even before another
            // layout pass. Revalidate before publishing into SwiftUI state.
            self.refreshLayout()
            guard self.heightRevision == revision, self.pendingHeight == height else { return }
            self.pendingHeight = nil
            self.reportedHeight = height
            self.onHeightChange?(height)
        }
    }
}

/// Short drafts grow instead of scrolling, even while the viewport catches up.
private final class DraftClipView: NSClipView {
    var permitsVerticalScrolling = false

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        bounds.origin.x = 0
        if !permitsVerticalScrolling { bounds.origin.y = 0 }
        return bounds
    }
}

final class DraftTextView: NSTextView {
    var permitsFocus = false
    var onSubmit: (() -> Bool)?
    var onFocusConversation: (() -> Void)?
    var onMoveCommandSelection: ((Int) -> Bool)?
    var onCompleteCommand: (() -> String?)?
    var onDismissCommands: (() -> Bool)?
    var userName = ""
    private var greeting = "What’s next?"
    private var hasSubmittedSinceOpening = false

    var placeholder: String {
        hasSubmittedSinceOpening ? "Send a message…" : greeting
    }

    func rotatePlaceholder(hour: Int = Calendar.current.component(.hour, from: .now)) {
        let prompts = OpeningGreetings.messages(userName: userName, hour: hour)
        greeting = prompts.filter { $0 != greeting }.randomElement()!
        hasSubmittedSinceOpening = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if event.keyCode == 8, modifiers == .control, isEditable {
            if !string.isEmpty {
                breakUndoCoalescing()
                insertText("", replacementRange: NSRange(location: 0, length: string.utf16.count))
                breakUndoCoalescing()
            }
            return
        }

        if (event.keyCode == 126 || event.keyCode == 125), modifiers.isEmpty,
           isEditable, !hasMarkedText(),
           onMoveCommandSelection?(event.keyCode == 126 ? -1 : 1) == true {
            return
        }

        if event.keyCode == 48, modifiers.isEmpty, isEditable, !hasMarkedText(),
           let completion = onCompleteCommand?() {
            if string != completion {
                breakUndoCoalescing()
                insertText(completion, replacementRange: NSRange(location: 0, length: string.utf16.count))
                breakUndoCoalescing()
            }
            setSelectedRange(NSRange(location: completion.utf16.count, length: 0))
            _ = onDismissCommands?()
            return
        }

        if event.keyCode == 48, modifiers.isEmpty || modifiers == .shift,
           !hasMarkedText(), let onFocusConversation {
            onFocusConversation()
            return
        }
        guard (event.keyCode == 36 || event.keyCode == 76), modifiers.isEmpty,
              !hasMarkedText(), let onSubmit else {
            super.keyDown(with: event)
            return
        }

        // Rejected sends still consume Return. The owner clears the binding on
        // acceptance; never overwrite it here after invoking the callback.
        let undoManager = undoManager
        if onSubmit() {
            hasSubmittedSinceOpening = true
            needsDisplay = true
            breakUndoCoalescing()
            undoManager?.removeAllActions()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let font else { return }
        (placeholder as NSString).draw(
            at: textContainerOrigin,
            withAttributes: [.font: font, .foregroundColor: NSColor.placeholderTextColor]
        )
    }

    override func scrollWheel(with event: NSEvent) {}

    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() { super.cancelOperation(sender) }
        else if onDismissCommands?() != true {
            _ = nextResponder?.tryToPerform(#selector(cancelOperation(_:)), with: sender)
        }
    }

    override var acceptsFirstResponder: Bool { permitsFocus && super.acceptsFirstResponder }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
