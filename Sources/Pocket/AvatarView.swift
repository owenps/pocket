import AppKit
import QuartzCore
import SwiftUI

struct AvatarView: View {
    let appearance: AvatarAppearance
    var size: CGFloat? = nil
    var behavior: AvatarAnimation.Behavior = .inactive
    var idleBlinkInterval: ClosedRange<TimeInterval> = 4...8

    var body: some View {
        AvatarImage(appearance: appearance, behavior: behavior,
                    idleBlinkInterval: idleBlinkInterval)
            .frame(width: size ?? appearance.size.points, height: size ?? appearance.size.points)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct AvatarImage: NSViewRepresentable {
    let appearance: AvatarAppearance
    let behavior: AvatarAnimation.Behavior
    let idleBlinkInterval: ClosedRange<TimeInterval>

    func makeNSView(context: Context) -> AvatarCanvas {
        AvatarCanvas()
    }

    func updateNSView(_ view: AvatarCanvas, context: Context) {
        view.update(appearance, behavior: behavior, idleBlinkInterval: idleBlinkInterval)
    }

    static func dismantleNSView(_ view: AvatarCanvas, coordinator: ()) {
        view.cleanUp()
    }
}

/// No image-derived intrinsic size: SwiftUI's explicit frame is the only size authority.
private final class AvatarCanvas: NSView {
    private var renderedAppearance: AvatarAppearance?
    private typealias Pose = AvatarAnimation.Pose

    private var images: [Pose: CGImage] = [:]
    private var speakingPosesCached = false
    private var pose = Pose()
    private var drawingOffset = CGPoint.zero
    private var transparentMargin = CGSize.zero
    private var animation = AvatarAnimation()
    private var requestedBehavior: AvatarAnimation.Behavior = .inactive
    private var requestedAppearance: AvatarAppearance?
    private var previewPending = false
    private var previewActive = false
    private var hasBeenAttached = false
    private var windowClosed = false
    private var idleBlinkInterval: ClosedRange<TimeInterval> = 4...8
    private var timer: Timer?
    private var scheduledDeadline: TimeInterval?
    private var displayLink: CADisplayLink?
    private weak var observedWindow: NSWindow?
    private let observedViews = NSHashTable<NSView>.weakObjects()

    // CADisplayLink retains its target; do not let the clock keep a detached canvas alive.
    @MainActor private final class DisplayTarget: NSObject {
        weak var canvas: AvatarCanvas?
        init(_ canvas: AvatarCanvas) { self.canvas = canvas }
        @objc func advance(_ link: CADisplayLink) { canvas?.advance(link) }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(visibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        MainActor.assumeIsolated {
            displayLink?.invalidate()
            timer?.invalidate()
        }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override var isOpaque: Bool { false }

    func update(_ appearance: AvatarAppearance, behavior: AvatarAnimation.Behavior,
                idleBlinkInterval: ClosedRange<TimeInterval>) {
        let newPreview = behavior == .preview
            && (requestedBehavior != .preview || requestedAppearance != appearance)
        // Display size does not change the artwork, but does request a new preview.
        var artwork = appearance
        artwork.size = .small
        if renderedAppearance != artwork || newPreview
            || (behavior != .preview
                && (self.idleBlinkInterval != idleBlinkInterval || requestedBehavior == .preview)) {
            stopClocks()
            animation = AvatarAnimation(blinkInterval: idleBlinkInterval)
        }
        requestedAppearance = appearance
        if newPreview {
            previewPending = true
            previewActive = false
        } else if behavior != .preview {
            previewPending = false
            previewActive = false
        }
        if renderedAppearance != artwork {
            renderedAppearance = artwork
            images.removeAll()
            speakingPosesCached = false
            let resting = AvatarRenderer.image(for: artwork)
            images[Pose()] = resting
            transparentMargin = resting.map(Self.transparentMargin) ?? .zero
            needsDisplay = true
        }
        self.idleBlinkInterval = idleBlinkInterval
        requestedBehavior = behavior
        updateMotion(at: CACurrentMediaTime())
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window != nil {
            previewPending = false
            previewActive = false
        }
        animation.update(behavior: .inactive, at: CACurrentMediaTime())
        stopClocks()
        applyPose()
        if let observedWindow { NotificationCenter.default.removeObserver(self, name: nil, object: observedWindow) }
        observedWindow = nil
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observedWindow = window
        if let window {
            hasBeenAttached = true
            windowClosed = false
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didExposeNotification,
                         NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: name, object: window)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(windowShown),
                name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose),
                name: NSWindow.willCloseNotification, object: window)
        }
        observeVisibleRect()
        visibilityChanged()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        observeVisibleRect()
        visibilityChanged()
    }

    private func observeVisibleRect() {
        for view in observedViews.allObjects {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: view)
            NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: view)
        }
        observedViews.removeAllObjects()
        var ancestor: NSView? = self
        while let view = ancestor {
            view.postsBoundsChangedNotifications = true
            view.postsFrameChangedNotifications = true
            observedViews.add(view)
            for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: name, object: view)
            }
            ancestor = view.superview
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        visibilityChanged()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        visibilityChanged()
    }

    override func layout() {
        super.layout()
        visibilityChanged()
    }

    private var canAnimate: Bool {
        !windowClosed && window?.isVisible == true
            && window?.occlusionState.contains(.visible) == true
            && !isHiddenOrHasHiddenAncestor && !visibleRect.intersection(bounds).isEmpty
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    @objc private func windowShown() {
        windowClosed = false
        visibilityChanged()
    }

    @objc private func visibilityChanged() {
        updateMotion(at: CACurrentMediaTime())
    }

    private func updateMotion(at time: TimeInterval) {
        let visible = canAnimate
        if previewPending, window != nil || hasBeenAttached {
            // Requests made behind a visibility/motion gate are consumed, not queued.
            previewPending = false
            previewActive = visible
        }
        if !visible { previewActive = false }
        let behavior = requestedBehavior == .preview
            ? (previewActive ? AvatarAnimation.Behavior.preview : .inactive)
            : (visible ? requestedBehavior : .inactive)
        animation.update(behavior: behavior, at: time)
        if animation.state == .previewBlink || animation.state == .speaking {
            cacheSpeakingPoses()
        } else if animation.state == .idle, animation.nextDeadline != nil {
            cache(Pose(eyes: .blink))
        }
        if animation.state == .speaking {
            startSpeaking()
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
        scheduleDeadline(at: time)
        applyPose()
    }

    private func cacheSpeakingPoses() {
        guard !speakingPosesCached else { return }
        speakingPosesCached = true
        // Cache before either preview clock starts; frame callbacks only select poses.
        for mouth in AvatarRenderer.Mouth.allCases {
            for eyes in AvatarRenderer.Eyes.allCases {
                cache(Pose(mouth: mouth, eyes: eyes))
            }
        }
    }

    private func startSpeaking() {
        guard displayLink == nil, let window else { return }
        let link = window.displayLink(target: DisplayTarget(self), selector: #selector(DisplayTarget.advance(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 8, preferred: 8)
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    private func advance(_ link: CADisplayLink) {
        guard displayLink === link else { return }
        updateMotion(at: CACurrentMediaTime())
    }

    private func scheduleDeadline(at time: TimeInterval) {
        guard let deadline = animation.nextDeadline else { cancelTimer(); return }
        guard scheduledDeadline != deadline else { return }
        cancelTimer()
        let timer = Timer(timeInterval: max(0.001, deadline - time), repeats: false) { [weak self] timer in
            let identity = ObjectIdentifier(timer)
            MainActor.assumeIsolated {
                guard let self, self.timer.map(ObjectIdentifier.init) == identity else { return }
                self.timer = nil
                self.scheduledDeadline = nil
                self.updateMotion(at: CACurrentMediaTime())
            }
        }
        self.timer = timer
        scheduledDeadline = deadline
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cache(_ pose: Pose) {
        guard images[pose] == nil, let appearance = renderedAppearance else { return }
        images[pose] = AvatarRenderer.image(for: appearance, mouth: pose.mouth, eyes: pose.eyes)
    }

    private func applyPose() {
        let next = animation.pose
        guard pose != next || drawingOffset != animation.drawingOffset else { return }
        pose = next
        drawingOffset = animation.drawingOffset
        needsDisplay = true
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
        scheduledDeadline = nil
    }

    private func stopClocks() {
        displayLink?.invalidate()
        displayLink = nil
        cancelTimer()
    }

    @objc private func windowWillClose() {
        windowClosed = true
        previewPending = false
        updateMotion(at: CACurrentMediaTime())
    }

    func cleanUp() {
        requestedBehavior = .inactive
        updateMotion(at: CACurrentMediaTime())
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        observedViews.removeAllObjects()
        observedWindow = nil
    }

    // Normalized transparent gutters keep even tiny/custom sizes from clipping hats.
    private static func transparentMargin(_ image: CGImage) -> CGSize {
        guard let bytes = image.dataProvider?.data as Data? else { return .zero }
        var minX = image.width, minY = image.height, maxX = 0, maxY = 0
        for y in 0..<image.height {
            for x in 0..<image.width where bytes[y * image.bytesPerRow + x * 4 + 3] != 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return CGSize(width: CGFloat(min(minX, image.width - 1 - maxX)) / CGFloat(image.width),
                      height: CGFloat(min(minY, image.height - 1 - maxY)) / CGFloat(image.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image = images[pose], let context = NSGraphicsContext.current?.cgContext else { return }
        let limitX = min(0.35, bounds.width * transparentMargin.width)
        let limitY = min(0.35, bounds.height * transparentMargin.height)
        let offset = CGPoint(x: min(limitX, max(-limitX, drawingOffset.x)),
                             y: min(limitY, max(-limitY, drawingOffset.y)))
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(image, in: bounds.offsetBy(dx: offset.x, dy: offset.y))
        context.restoreGState()
    }
}
