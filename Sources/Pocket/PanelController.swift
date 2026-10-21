import AppKit
import Observation
import QuartzCore
import SwiftUI

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: CapturePanel
    private let state: PanelState
    private var geometry: IslandGeometry?
    private var motion = IslandMotion()
    private var buddyEntrance = BuddyEntranceMotion()
    private var expandedLayout: IslandLayout?
    private var displayLink: CADisplayLink?
    private var previousFrameTime: CFTimeInterval?

    init(state: PanelState) {
        self.state = state
        panel = CapturePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.title = "Pocket"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // AppKit's automatic ordering fade competes with the notch spring and
        // briefly removes the whole island when releasing keyboard focus.
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.delegate = self
        panel.onCollapse = { [weak self] in self?.collapse() }
        let hostingView = IslandHostingView(rootView: PanelView(
            state: state,
            expand: { [weak self] in self?.show() },
            collapse: { [weak self] in self?.collapse() },
            editorHeightChanged: { [weak self] in self?.updateEditorHeight($0) },
            submit: { [weak self] in self?.submitDraft() ?? false },
            transcriptHeightChanged: { [weak self] in self?.updateTranscriptHeight($0) }
        ))
        // Window geometry owns the size, not the editor's intrinsic size.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        NotificationCenter.default.addObserver(
            self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
    }

    func start() {
        observeComposerHeight()
        updateGeometry()
        resize(animated: false)
        // A quiet island at launch, without taking keyboard focus.
        panel.orderFrontRegardless()
    }

    func toggle() {
        if state.isExpanded { collapse() } else { show() }
    }

    func show() {
        let freshOpening = !state.isExpanded && motion.isSettled
        updateGeometry()
        state.openPanel(resuming: !motion.isSettled)
        panel.acceptsKeyboardFocus = true
        resize(animated: panel.isVisible, seedHiddenContent: freshOpening)
        panel.makeKeyAndOrderFront(nil)
        state.focusRequest &+= 1
    }

    func collapse() {
        guard state.isExpanded else { return }
        // Presentation never owns draft, conversation, or execution lifetime.
        state.closePanel()
        panel.acceptsKeyboardFocus = false
        // Withdrawing releases nonactivating-panel keyboard focus to the prior app.
        // Ordering front again keeps the collapsed island visible, without key focus.
        panel.orderOut(nil)
        panel.orderFrontRegardless()
        resize(animated: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        collapse()
    }

    private func submitDraft() -> Bool {
        guard state.submitDraft() else { return false }
        resize(animated: panel.isVisible)
        return true
    }

    func resetConversation() {
        state.resetConversation()
        expandedLayout = nil
        resize(animated: state.isExpanded && panel.isVisible)
    }

    private func updateEditorHeight(_ height: CGFloat) {
        guard height.isFinite else { return }
        let height = min(DraftEditor.maximumHeight, max(0, height))
        guard abs(state.editorHeight - height) >= 0.5 else { return }
        state.editorHeight = height
    }

    private func observeComposerHeight() {
        withObservationTracking {
            _ = state.composerHeight
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeComposerHeight()
                if self.state.isExpanded { self.resize(animated: self.panel.isVisible) }
            }
        }
    }

    private func updateTranscriptHeight(_ height: CGFloat) {
        guard height.isFinite, height >= 0,
              abs(state.naturalTranscriptHeight - height) >= 0.5 else { return }
        state.naturalTranscriptHeight = height
        // Hidden measurements prepare the next opening, never start idle animation.
        if state.isExpanded { resize(animated: panel.isVisible) }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        previousFrameTime = nil
    }

    @objc private func displaysChanged() {
        expandedLayout = nil
        updateGeometry()
        resize(animated: false)
    }

    @objc private func accessibilityOptionsChanged() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            resize(animated: false)
        }
    }

    private func updateGeometry() {
        // One stable island: prefer the physical notch, otherwise the primary display.
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.screens.first else { return }
        let geometry = IslandGeometry(
            screenFrame: screen.frame,
            notchHeight: screen.safeAreaInsets.top,
            topLeftArea: screen.auxiliaryTopLeftArea,
            topRightArea: screen.auxiliaryTopRightArea
        )
        self.geometry = geometry
        state.notchHeight = geometry.notchHeight
        state.collapsedSize = geometry.collapsedSize
    }

    private func resize(animated: Bool, seedHiddenContent: Bool = false) {
        guard let geometry else { return }
        if state.isExpanded || expandedLayout == nil {
            expandedLayout = geometry.expandedLayout(
                composerHeight: state.composerHeight,
                naturalTranscriptHeight: state.presentedMessages.isEmpty ? 0 : state.naturalTranscriptHeight,
                includesError: state.shortcutError != nil
            )
            expandedLayout?.editorHeight = state.editorHeight
        }
        guard let expandedLayout else { return }
        if seedHiddenContent {
            var initial = expandedLayout
            initial.size = motion.layout.size
            motion = IslandMotion(layout: initial)
        }
        var target = expandedLayout
        if !state.isExpanded { target.size = geometry.collapsedSize }
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        motion.retarget(to: target, expanded: state.isExpanded, animated: animate)
        render()
        guard !motion.isSettled || buddyEntrance.isActive else {
            stop()
            return
        }
        guard displayLink == nil else { return }
        let link = panel.displayLink(target: self, selector: #selector(advance(_:)))
        previousFrameTime = nil
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func advance(_ link: CADisplayLink) {
        let time = link.targetTimestamp
        // Start with one display interval, not wall time mixed with the first
        // future target timestamp. Subsequent frames preserve elapsed-time catchup.
        let elapsed = max(0, time - (previousFrameTime ?? link.timestamp))
        previousFrameTime = time
        motion.advance(by: elapsed)
        render(elapsed: elapsed)
        if motion.isSettled && !buddyEntrance.isActive { stop() }
    }

    private func render(elapsed: TimeInterval = 0) {
        guard let geometry, let expandedLayout else { return }
        let sample = motion.layout
        let widthRange = expandedLayout.size.width - geometry.collapsedSize.width
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state.expansionProgress = widthRange > 0
                ? (sample.size.width - geometry.collapsedSize.width) / widthRange
                : (state.isExpanded ? 1 : 0)
            state.expandedSize = expandedLayout.size
            state.displayedEditorHeight = min(DraftEditor.maximumHeight, max(0, sample.editorHeight))
            state.displayedComposerHeight = max(0, sample.composerHeight)
            state.transcriptHeight = min(112, max(0, sample.transcriptHeight))
            state.transcriptGap = min(10, max(0, sample.transcriptGap))
            state.contentHeight = state.notchHeight + 28 + state.displayedComposerHeight
                + state.transcriptHeight + state.transcriptGap + (state.shortcutError == nil ? 0 : 48)
            let frame = IslandFrame(surface: geometry.frame(size: sample.size))
            // AppKit rounds window bounds outward to whole points. Paint the
            // fractional surface inside those tight bounds instead of stretching
            // it to the rounded window, which caused the final 2px close snap.
            panel.setFrame(frame.window, display: false)
            state.surfaceRect = frame.localSurface(in: panel.frame)
            buddyEntrance.update(
                expanded: state.isExpanded,
                contentVisibility: IslandMotion.contentVisibility(
                    surfaceSize: state.surfaceRect.size, expandedSize: state.expandedSize,
                    expansionProgress: state.expansionProgress
                ),
                elapsed: elapsed
            )
            state.buddyEntranceProgress = buddyEntrance.progress
        }
        // Resolve geometry before the normal display pass, rather than drawing
        // the resized window synchronously with a potentially stale SwiftUI mask.
        panel.contentView?.layoutSubtreeIfNeeded()
    }
}

private final class CapturePanel: NSPanel {
    var acceptsKeyboardFocus = false
    var onCollapse: (() -> Void)?

    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCollapse?()
    }
}

private final class IslandHostingView: NSHostingView<PanelView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
