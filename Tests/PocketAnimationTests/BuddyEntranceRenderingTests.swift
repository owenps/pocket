import AppKit
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct BuddyEntranceRenderingTests {
    @Test(arguments: [false, true], AvatarAppearance.Size.allCases)
    func entrancePopsOnlyBuddyWithoutEditorDrift(reduceMotion: Bool, size: AvatarAppearance.Size) throws {
        _ = NSApplication.shared
        let name = "BuddyEntranceRenderingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let conversation = ConversationSession(backend: DemoAssistantBackend(), defaults: defaults)
        conversation.draft = "Draft stays visible"
        let state = PanelState(conversation: conversation, defaults: defaults)
        state.avatar.size = size
        state.avatar.headwear = .mushroom
        state.displayedComposerHeight = state.composerHeight
        state.isExpanded = true
        state.expansionProgress = 1
        state.showBuddy = true
        state.transcriptHeight = 0
        state.transcriptGap = 0
        state.contentHeight = state.bodyLayout.height
        state.expandedSize = CGSize(width: 460, height: state.contentHeight)
        state.surfaceRect = CGRect(origin: .zero, size: state.expandedSize)
        state.buddyEntranceProgress = 0

        let window = NSWindow(
            contentRect: state.surfaceRect, styleMask: .borderless, backing: .buffered, defer: true
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        // Never order the window: native idle/blink clocks stay inactive.
        let host = NSHostingView(rootView: PanelView(
            state: state, expand: {}, collapse: {}, editorHeightChanged: { _ in }, submit: { false }
        )
        // SwiftUI exposes the writable accessibility override under this name.
        .environment(\._accessibilityReduceMotion, reduceMotion)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        })
        host.sizingOptions = []
        window.contentView = host
        defer { window.contentView = nil }

        // Fixed 2× bitmap coordinates, with room for Buddy's entrance travel.
        let buddy = CGRect(x: 24 * 2, y: 12 * 2,
                           width: state.avatar.size.points * 2, height: state.avatar.size.points * 2)
        let envelope = buddy.insetBy(dx: -8, dy: -16)
        var images: [NSBitmapImageRep] = []
        var frames: [CGRect] = []
        var editors: [NSTextView] = []
        let hostFrame = host.frame
        let peakProgress = (reduceMotion ? 0.18 : 0.14) / 0.34
        for progress in [0.0, 0.1, peakProgress, 1.0] {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { state.buddyEntranceProgress = progress }
            try wait(host) {
                guard let editor = textViews(in: host).first(where: { $0.isEditable }),
                      editor.string == conversation.draft else { return false }
                let mass = ink(in: try snapshot(host), rect: envelope).mass
                guard let previous = images.last else { return mass < 0.01 }
                let previousMass = ink(in: previous, rect: envelope).mass
                if progress < 1 { return mass > previousMass + 1 }
                return reduceMotion ? abs(mass - previousMass) < 1 : mass < previousMass - 1
            }
            let editor = try #require(textViews(in: host).first { $0.isEditable })
            let viewport = try #require(editor.enclosingScrollView)
            editors.append(editor)
            frames.append(viewport.convert(viewport.bounds, to: host))
            images.append(try snapshot(host))
            #expect(host.frame == hostFrame)
            #expect(editor.string == conversation.draft)
            #expect(state.expansionProgress == 1)
            #expect(state.surfaceRect.size == state.expandedSize)
        }
        #expect(editors.allSatisfy { $0 === editors[0] })
        #expect(frames.allSatisfy { $0 == frames[0] })
        try #require(frames[0].width > 0 && frames[0].height > 0)

        let hidden = ink(in: images[0], rect: envelope)
        let arriving = ink(in: images[1], rect: envelope)
        let peak = ink(in: images[2], rect: envelope)
        let visible = ink(in: images[3], rect: envelope)
        let topRay = CGRect(x: buddy.midX - 2, y: buddy.minY - 4, width: 4, height: 2)
        let burstMass = ink(in: images[2], rect: topRay).mass
        if reduceMotion {
            #expect(burstMass < 0.01)
        } else {
            #expect(burstMass > 1)
        }
        #expect(ink(in: images[0], rect: topRay).mass < 0.01)
        #expect(ink(in: images[3], rect: topRay).mass < 0.01)
        #expect(hidden.mass < 0.01)
        try #require(visible.mass > 100)
        #expect(arriving.mass > 1 && arriving.mass < visible.mass)
        if reduceMotion {
            #expect(abs(arriving.centerY - visible.centerY) < 0.6)
            #expect(abs(peak.mass - visible.mass) < 1)
        } else {
            #expect(peak.mass > visible.mass * 1.1)
            #expect(peak.centerY < visible.centerY - 0.5)
        }
        #expect(abs(peak.centerX - visible.centerX) < 1.5)
        #expect(ink(in: images[3], rect: buddy).mass > visible.mass * 0.99)

        // The editor is already painted at progress zero; no parent fade, rise,
        // resizing, or other changed pixels outside the Buddy's travel envelope.
        let editorRect = CGRect(x: frames[0].minX * 2, y: frames[0].minY * 2,
                                width: frames[0].width * 2, height: frames[0].height * 2)
        #expect(ink(in: images[0], rect: editorRect).mass > 10)
        for image in images.dropFirst() {
            #expect(maximumDifference(images[0], image, excluding: envelope) <= 2.0 / 255)
        }
    }

    private func textViews(in view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap { textViews(in: $0) }
    }

    private func snapshot(_ view: NSView) throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    // The surface is black: RGB energy isolates Buddy/text ink, not surface alpha.
    private func ink(in image: NSBitmapImageRep, rect: CGRect) -> (mass: Double, centerX: Double, centerY: Double) {
        var mass = 0.0, sumX = 0.0, sumY = 0.0
        for y in max(0, Int(rect.minY))..<min(image.pixelsHigh, Int(rect.maxY)) {
            for x in max(0, Int(rect.minX))..<min(image.pixelsWide, Int(rect.maxX)) {
                guard let color = image.colorAt(x: x, y: y) else { continue }
                let weight = (color.redComponent + color.greenComponent + color.blueComponent) * color.alphaComponent
                mass += weight
                sumX += Double(x) * weight
                sumY += Double(y) * weight
            }
        }
        return (mass, sumX / max(mass, 0.001), sumY / max(mass, 0.001))
    }

    private func wait(_ view: NSView, until condition: () throws -> Bool) throws {
        let deadline = Date(timeIntervalSinceNow: 2)
        repeat {
            view.layoutSubtreeIfNeeded()
            if try condition() { return }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        } while Date() < deadline
        try #require(try condition(), "Expected entrance rendering before timeout")
    }

    private func maximumDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, excluding rect: CGRect) -> Double {
        var difference = 0.0
        for y in 0..<lhs.pixelsHigh {
            for x in 0..<lhs.pixelsWide where !rect.contains(CGPoint(x: x, y: y)) {
                guard let a = lhs.colorAt(x: x, y: y), let b = rhs.colorAt(x: x, y: y) else { continue }
                difference = max(difference, abs(a.redComponent - b.redComponent),
                                 abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent),
                                 abs(a.alphaComponent - b.alphaComponent))
            }
        }
        return difference
    }
}
