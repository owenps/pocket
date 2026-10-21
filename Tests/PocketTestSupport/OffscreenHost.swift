import AppKit
import SwiftUI

@MainActor
public class OffscreenTestWindow: NSWindow {
    public var shown = true
    public var key = true
    public var exposed = true

    public override var canBecomeKey: Bool { true }
    public override var isVisible: Bool { shown }
    public override var isKeyWindow: Bool { shown && key }
    public override var occlusionState: NSWindow.OcclusionState { shown && exposed ? [.visible] : [] }
}

@MainActor
public final class OffscreenHost<Content: View> {
    public let view: NSHostingView<Content>
    public let window: OffscreenTestWindow

    public init(_ content: Content, size: CGSize) {
        _ = NSApplication.shared
        view = NSHostingView(rootView: content)
        view.sizingOptions = []
        window = OffscreenTestWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: .borderless, backing: .buffered, defer: true
        )
        window.contentView = view
    }

    public func close() { window.contentView = nil }
}
