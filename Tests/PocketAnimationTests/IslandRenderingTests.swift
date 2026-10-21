import AppKit
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct IslandRenderingTests {
    @Test func finalFractionalHeightDoesNotPaintAnExtraWindowRow() throws {
        let fractional = try paintedHeight(surfaceHeight: 38.001)
        let rest = try paintedHeight(surfaceHeight: 38)
        // Retina reproduction: AppKit hosts the first surface in a 39pt window.
        // Its extra two pixels must stay transparent instead of snapping away.
        #expect(abs(fractional - rest) <= 1)
        #expect(abs(rest - 76) <= 1)
    }

    private func paintedHeight(surfaceHeight: CGFloat) throws -> Int {
        _ = NSApplication.shared
        let name = "IslandRenderingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = ConversationSession(backend: DemoAssistantBackend(), defaults: defaults)
        let state = PanelState(conversation: session, defaults: defaults)
        state.expandedSize = CGSize(width: 460, height: 126)
        state.notchHeight = 38
        let frame = IslandFrame(surface: CGRect(
            x: 500 - 253.001 / 2, y: 500 - surfaceHeight,
            width: 253.001, height: surfaceHeight
        ))
        let window = NSWindow(contentRect: frame.window, styleMask: .borderless, backing: .buffered, defer: true)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        state.surfaceRect = frame.localSurface(in: window.frame)
        let host = NSHostingView(rootView: PanelView(
            state: state, expand: {}, collapse: {}, editorHeightChanged: { _ in }, submit: { false }
        ))
        host.sizingOptions = []
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        host.layoutSubtreeIfNeeded()
        let image = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        image.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: image)
        return (0..<image.pixelsHigh).filter {
            (image.colorAt(x: image.pixelsWide / 2, y: $0)?.alphaComponent ?? 0) > 0.5
        }.count
    }
}
