import AppKit
import QuartzCore
import SwiftUI

private let thinkingAttribute = NSAttributedString.Key("PocketThinking")

/// The parent supplies the viewport; only the native document grows.
struct ConversationView: NSViewRepresentable {
    var messages: [ConversationMessage]
    var phase: ReplyPhase
    var isExpanded: Bool
    var focusRequest: Int
    var onFocusComposer: () -> Void
    var animateThinking: Bool = true
    var onReplyViewed: ((UUID) -> Void)? = nil
    var onContentHeightChanged: ((CGFloat) -> Void)? = nil
    var fontSize: Double = Double(NSFont.preferredFont(forTextStyle: .body).pointSize)

    func makeNSView(context: Context) -> ConversationScrollView {
        let view = ConversationScrollView(frame: .zero)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: ConversationScrollView, context: Context) {
        view.transcript.onFocusComposer = onFocusComposer
        view.setExpanded(isExpanded, focusRequest: focusRequest)
        view.configure(animateThinking: animateThinking, onReplyViewed: onReplyViewed,
                       onContentHeightChanged: onContentHeightChanged)
        view.setConversation(messages, phase: phase, fontSize: fontSize)
    }

    static func dismantleNSView(_ view: ConversationScrollView, coordinator: ()) {
        view.cleanUp()
    }
}

final class ConversationScrollView: NSScrollView {
    let transcript: ConversationTextView
    private var isMeasuring = false
    private var requestedFocus: Int?
    private var fulfilledFocus: Int?
    private var pendingScroll: (followsBottom: Bool, origin: NSPoint)?
    private var lastUserID: UUID?
    private var readableReplyID: UUID?
    private var viewedReplyID: UUID?
    private var receiptPending = false
    private var animateThinking = true
    private var onReplyViewed: ((UUID) -> Void)?
    private var onContentHeightChanged: ((CGFloat) -> Void)?
    private var pendingHeightReport: DispatchWorkItem?
    private var pendingHeight: CGFloat?
    private var reportedHeight: CGFloat?
    private weak var observedWindow: NSWindow?

    override init(frame frameRect: NSRect) {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        transcript = ConversationTextView(frame: .zero, textContainer: container)
        super.init(frame: frameRect)

        borderType = .noBorder
        drawsBackground = false
        focusRingType = .none
        hasHorizontalScroller = false
        hasVerticalScroller = false
        autohidesScrollers = true
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none

        transcript.isEditable = false
        transcript.isSelectable = true
        transcript.isRichText = false
        transcript.importsGraphics = false
        transcript.usesFontPanel = false
        transcript.allowsUndo = false
        transcript.drawsBackground = false
        transcript.focusRingType = .none
        transcript.font = NSFont.preferredFont(forTextStyle: .body)
        transcript.textColor = .labelColor
        transcript.textContainerInset = NSSize(width: 0, height: 2)
        transcript.isHorizontallyResizable = false
        transcript.isVerticallyResizable = true
        transcript.minSize = .zero
        transcript.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        transcript.autoresizingMask = [.width]
        transcript.setAccessibilityLabel("Conversation")
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        documentView = transcript
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged),
                                               name: NSView.boundsDidChangeNotification, object: contentView)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(visibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func scrollWheel(with event: NSEvent) {}

    override func setFrameSize(_ newSize: NSSize) {
        // AppKit can resize during initialization, before the document exists.
        let installed = documentView === transcript
        if installed, newSize != frame.size, pendingScroll == nil {
            let viewport = contentView.bounds
            pendingScroll = (viewport.width <= 0 || viewport.height <= 0 || isAtBottom, viewport.origin)
        }
        super.setFrameSize(newSize)
        if installed { refreshLayout() }
    }

    override func layout() {
        super.layout()
        refreshLayout()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observedWindow { NotificationCenter.default.removeObserver(self, name: nil, object: observedWindow) }
        observedWindow = window
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didExposeNotification,
                         NSWindow.didBecomeKeyNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: name, object: window)
            }
        }
        visibilityChanged()
    }

    override func viewDidHide() {
        super.viewDidHide()
        visibilityChanged()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        // Descendants can still report hidden until AppKit finishes unhiding.
        DispatchQueue.main.async { [weak self] in
            self?.visibilityChanged()
        }
    }

    func configure(animateThinking: Bool = true, onReplyViewed: ((UUID) -> Void)? = nil,
                   onContentHeightChanged: ((CGFloat) -> Void)? = nil) {
        self.animateThinking = animateThinking
        self.onReplyViewed = onReplyViewed
        self.onContentHeightChanged = onContentHeightChanged
        if onContentHeightChanged == nil {
            cancelHeightReport()
            reportedHeight = nil
        }
        refreshLayout()
    }

    private func cancelHeightReport() {
        pendingHeightReport?.cancel()
        pendingHeightReport = nil
        pendingHeight = nil
    }

    private func reportContentHeight(_ height: CGFloat) {
        guard height.isFinite, onContentHeightChanged != nil else { return }
        pendingHeight = height
        guard pendingHeightReport == nil else { return }
        guard reportedHeight.map({ abs($0 - height) < 0.5 }) != true else { return }
        let report = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHeightReport = nil
            guard let height = self.pendingHeight, let callback = self.onContentHeightChanged else { return }
            self.pendingHeight = nil
            guard self.reportedHeight.map({ abs($0 - height) < 0.5 }) != true else { return }
            self.reportedHeight = height
            callback(height)
        }
        pendingHeightReport = report
        DispatchQueue.main.async(execute: report)
    }

    func cleanUp() {
        onReplyViewed = nil
        onContentHeightChanged = nil
        cancelHeightReport()
        transcript.onFocusComposer = nil
        transcript.permitsFocus = false
        requestedFocus = nil
        transcript.setThinkingAnimation(false)
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private var isRevealed: Bool {
        transcript.permitsFocus && window?.isVisible == true
            && window?.occlusionState.contains(.visible) == true
            && !transcript.isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty
    }

    private var isAtBottom: Bool {
        contentView.bounds.height > 0 && contentView.bounds.maxY >= transcript.frame.maxY - 2
    }

    private func replyEligibleForReceipt() -> UUID? {
        guard isRevealed, window?.isKeyWindow == true, isAtBottom, onReplyViewed != nil, let readableReplyID,
              let text = transcript.textStorage, text.length > 0,
              transcript.isFinalLineVisible
        else { return nil }
        return readableReplyID
    }

    @objc fileprivate func visibilityChanged() {
        fulfillFocusRequest()
        transcript.setThinkingAnimation(isRevealed && animateThinking
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && transcript.isRangeVisible(transcript.thinkingRange))
        guard !receiptPending, let id = replyEligibleForReceipt(), id != viewedReplyID else { return }
        receiptPending = true
        // Layout and clip-view notifications can run during a SwiftUI update.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.receiptPending = false
            guard let current = self.replyEligibleForReceipt(), current == id, current != self.viewedReplyID else {
                self.visibilityChanged()
                return
            }
            self.viewedReplyID = current
            self.onReplyViewed?(current)
        }
    }

    func setExpanded(_ expanded: Bool, focusRequest: Int) {
        transcript.permitsFocus = expanded
        requestedFocus = focusRequest
        if focusRequest == 0 { fulfilledFocus = nil }
        visibilityChanged()
    }

    private func fulfillFocusRequest() {
        guard isRevealed, let requestedFocus, requestedFocus > 0,
              requestedFocus != fulfilledFocus, let window else { return }
        if window.makeFirstResponder(transcript) {
            fulfilledFocus = requestedFocus
        }
    }

    func setConversation(_ messages: [ConversationMessage], phase: ReplyPhase,
                         fontSize: Double = Double(NSFont.preferredFont(forTextStyle: .body).pointSize)) {
        let userID = messages.last(where: { $0.role == .user })?.id
        let newTurn = userID != nil && userID != lastUserID
        lastUserID = userID
        let reply = messages.last
        readableReplyID = phase == .idle && reply?.role == .assistant
            && (reply?.text.isEmpty == false || reply?.isStopped == true || reply?.failure != nil) ? reply?.id : nil
        let rendered = Self.render(messages, phase: phase, fontSize: fontSize)
        guard let storage = transcript.textStorage else { return }
        let changed = !storage.isEqual(to: rendered)
        guard changed || newTurn else { visibilityChanged(); return }

        if newTurn {
            pendingScroll = (true, .zero)
        } else if pendingScroll == nil {
            let viewport = contentView.bounds
            pendingScroll = (viewport.width <= 0 || viewport.height <= 0 || isAtBottom, viewport.origin)
        }
        guard changed else { refreshLayout(); return }
        let selections = transcript.selectedRanges
        storage.setAttributedString(rendered)
        transcript.thinkingRange = NSRange(location: NSNotFound, length: 0)
        rendered.enumerateAttribute(thinkingAttribute, in: NSRange(location: 0, length: rendered.length)) { value, range, _ in
            if value != nil { transcript.thinkingRange = range }
        }
        // Streaming must not discard a reader's selection, even when the new
        // document is shorter (e.g. a stopped empty reply gains its fallback).
        transcript.selectedRanges = selections.map { value in
            let range = value.rangeValue
            let start = min(range.location, storage.length)
            return NSValue(range: NSRange(location: start, length: min(range.length, storage.length - start)))
        }
        refreshLayout()
    }

    /// TextKit 1 measures the real wrapped document, never an estimated line count.
    func refreshLayout() {
        guard documentView === transcript, !isMeasuring else { return }
        isMeasuring = true
        defer {
            isMeasuring = false
            visibilityChanged()
        }
        tile()
        let width = contentView.bounds.width
        guard width.isFinite, width > 0,
              let container = transcript.textContainer, let manager = transcript.layoutManager else { return }
        transcript.setFrameSize(NSSize(width: width, height: max(transcript.frame.height, contentSize.height)))
        manager.ensureLayout(for: container)
        var bottom = manager.usedRect(for: container).maxY
        if manager.extraLineFragmentTextContainer === container {
            bottom = max(bottom, manager.extraLineFragmentRect.maxY)
        }
        let height = ceil(bottom + transcript.textContainerInset.height * 2)
        guard height.isFinite else { return }
        reportContentHeight(height)
        transcript.setFrameSize(NSSize(width: width, height: max(height, contentSize.height)))
        // NSTextView can shift its origin while fitting text during host resize.
        // Scrolling belongs to the clip view, never a negatively positioned document.
        transcript.setFrameOrigin(.zero)
        if let pendingScroll, contentView.bounds.height > 0 {
            let bottom = max(0, transcript.frame.height - contentView.bounds.height)
            let y = pendingScroll.followsBottom ? bottom : min(max(0, pendingScroll.origin.y), bottom)
            contentView.scroll(to: NSPoint(x: 0, y: y))
            reflectScrolledClipView(contentView)
            self.pendingScroll = nil
        }
    }

    private static func render(_ messages: [ConversationMessage], phase: ReplyPhase, fontSize: Double) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let nativeFont = NSFont.preferredFont(forTextStyle: .body)
        let size = fontSize.isFinite && fontSize > 0 ? CGFloat(fontSize) : nativeFont.pointSize
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont(descriptor: nativeFont.fontDescriptor, size: size) ?? nativeFont,
            .foregroundColor: NSColor.labelColor,
        ]
        let label: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize * size / nativeFont.pointSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        for (index, message) in messages.enumerated() {
            let stopped = message.role == .assistant && message.isStopped
            let failure = message.role == .assistant ? message.failure : nil
            let working = message.role == .assistant && message.text.isEmpty && message.outcome == nil
                && index == messages.count - 1 && phase != .idle
            let status = stopped ? "Reply stopped." : failure.map { "Reply failed: \($0)" }
            let text = working ? "thinking..." : (message.text.isEmpty ? status ?? "" : message.text)
            guard !text.isEmpty else { continue }
            if result.length > 0 { result.append(NSAttributedString(string: "\n\n", attributes: body)) }
            var attributes = body
            if message.role == .user || working { attributes[.foregroundColor] = NSColor.secondaryLabelColor }
            if working { attributes[thinkingAttribute] = true }
            result.append(NSAttributedString(string: text, attributes: attributes))
            if !message.text.isEmpty {
                if stopped {
                    result.append(NSAttributedString(string: "\nStopped.", attributes: label))
                } else if let failure {
                    result.append(NSAttributedString(string: "\nReply failed: \(failure)", attributes: label))
                }
            }
        }
        return result
    }
}

final class ConversationTextView: NSTextView {
    var permitsFocus = false
    var onFocusComposer: (() -> Void)?
    fileprivate var thinkingRange = NSRange(location: NSNotFound, length: 0)
    private var thinkingDisplayLink: CADisplayLink?

    fileprivate func isRangeVisible(_ range: NSRange) -> Bool {
        guard let rect = glyphRect(for: range) else { return false }
        return visibleRect.intersects(rect)
    }

    fileprivate var isFinalLineVisible: Bool {
        guard let layoutManager, let textContainer, layoutManager.numberOfGlyphs > 0 else { return false }
        layoutManager.ensureLayout(for: textContainer)
        let line = layoutManager.extraLineFragmentTextContainer === textContainer
            ? layoutManager.extraLineFragmentRect
            : layoutManager.lineFragmentRect(forGlyphAt: layoutManager.numberOfGlyphs - 1, effectiveRange: nil)
        let rect = line.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        return rect.height > 0 && visibleRect.minY <= rect.minY && visibleRect.maxY >= rect.maxY
    }

    private func glyphRect(for range: NSRange) -> NSRect? {
        guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= (textStorage?.length ?? 0),
              let layoutManager, let textContainer else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        if rect.isEmpty { rect = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil) }
        return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    fileprivate func setThinkingAnimation(_ enabled: Bool) {
        if enabled, thinkingDisplayLink == nil, let window {
            let link = window.displayLink(target: self, selector: #selector(advanceThinking))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            thinkingDisplayLink = link
            link.add(to: .main, forMode: .common)
            needsDisplay = true
        } else if !enabled, let link = thinkingDisplayLink {
            link.invalidate()
            thinkingDisplayLink = nil
            needsDisplay = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setThinkingAnimation(false) }
    }

    @objc private func advanceThinking(_ link: CADisplayLink) {
        (enclosingScrollView as? ConversationScrollView)?.visibilityChanged()
        if thinkingDisplayLink != nil, let rect = glyphRect(for: thinkingRange) { setNeedsDisplay(rect) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard thinkingDisplayLink != nil, let rect = glyphRect(for: thinkingRange), rect.intersects(dirtyRect),
              let layoutManager, let context = NSGraphicsContext.current?.cgContext else { return }
        let colors = [NSColor(white: 0.55, alpha: 1).cgColor, NSColor(white: 0.82, alpha: 1).cgColor,
                      NSColor(white: 0.55, alpha: 1).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])
        else { return }
        let band = max(40, rect.width * 0.65)
        let progress = CGFloat(CACurrentMediaTime().truncatingRemainder(dividingBy: 2.4) / 2.4)
        let center = rect.minX - band + progress * (rect.width + band * 2)
        context.saveGState()
        context.clip(to: rect)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        layoutManager.drawGlyphs(forGlyphRange: layoutManager.glyphRange(forCharacterRange: thinkingRange,
                                                                       actualCharacterRange: nil), at: textContainerOrigin)
        context.setBlendMode(.sourceIn)
        context.drawLinearGradient(gradient, start: CGPoint(x: center - band, y: rect.midY),
                                   end: CGPoint(x: center + band, y: rect.midY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.endTransparencyLayer()
        context.restoreGState()
    }

    override var acceptsFirstResponder: Bool { permitsFocus && super.acceptsFirstResponder }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func scrollWheel(with event: NSEvent) {}

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if (event.keyCode == 48 && (modifiers.isEmpty || modifiers == .shift))
            || ((event.keyCode == 36 || event.keyCode == 76) && modifiers.isEmpty) {
            onFocusComposer?()
            return
        }
        // All scrolling, selection and copy bindings remain AppKit's. Escape's
        // cancelOperation travels up the responder chain to the panel owner.
        super.keyDown(with: event)
    }

    override func insertTab(_ sender: Any?) { onFocusComposer?() }
    override func insertBacktab(_ sender: Any?) { onFocusComposer?() }
    override func insertNewline(_ sender: Any?) { onFocusComposer?() }
    override func cancelOperation(_ sender: Any?) {
        _ = nextResponder?.tryToPerform(#selector(cancelOperation(_:)), with: sender)
    }
}
