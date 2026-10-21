import AppKit
import PocketTestSupport
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct StopButtonAnimationTests {
    @Test(arguments: [false, true])
    func stopFadesWithoutMovingOrReplacingTheDraft(reduceMotion: Bool) throws {
        NativeAccessibility.enable()
        let name = "StopButtonAnimationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let conversation = ConversationSession(
            backend: DemoAssistantBackend(delay: { _ in try await Task.sleep(for: .seconds(60)) }),
            defaults: defaults
        )
        defer { conversation.stopReply() }
        let state = PanelState(conversation: conversation, defaults: defaults)
        state.isExpanded = true
        state.expansionProgress = 1
        state.showBuddy = false
        state.displayedComposerHeight = state.composerHeight
        state.transcriptHeight = 112
        state.transcriptGap = 10
        state.contentHeight = state.bodyLayout.height
        state.expandedSize = CGSize(width: 460, height: state.contentHeight)
        state.surfaceRect = CGRect(origin: .zero, size: state.expandedSize)
        conversation.draft = "Retained next draft"
        let fixture = OffscreenHost(PanelView(
            state: state, expand: {}, collapse: {}, editorHeightChanged: { _ in },
            submit: { state.submitDraft() }
        ).environment(\._accessibilityReduceMotion, reduceMotion), size: state.expandedSize)
        defer { fixture.close() }
        let host = fixture.view
        try NativeUITestSupport.wait {
            host.layoutSubtreeIfNeeded()
            return draftEditor(in: host)?.string == conversation.draft
        }
        let editor = try #require(draftEditor(in: host))
        let viewport = try #require(editor.enclosingScrollView)
        let editorFrame = viewport.convert(viewport.bounds, to: host)
        let accessibility = NativeAccessibility(host)
        func checkDraft() throws {
            #expect(draftEditor(in: host) === editor)
            #expect(editor.string == "Retained next draft")
            #expect(conversation.draft == editor.string)
            #expect(viewport.convert(viewport.bounds, to: host) == editorFrame)
        }

        // Exercise the first response from an idle mount, then a subsequent one.
        for _ in 0..<2 {
            let idle = try snapshot(host)
            #expect(state.submitDraft())
            conversation.draft = "Retained next draft"
            let appearing = try sample(host, checking: checkDraft)
            let stop = try #require(accessibility.descendant(identifier: "stop-reply"))
            let crop = host.convert(fixture.window.convertFromScreen(stop.frame), from: nil)
            try #require(crop.width > 0 && crop.height > 0 && host.bounds.contains(crop))
            let settled = try snapshot(host)
            let off = brightness(idle, in: crop)
            let on = brightness(settled, in: crop)
            let incoming = appearing.map { brightness($0, in: crop) }
            #expect(off < 1)
            try #require(on > off + 100, "The active Stop button must actually be painted")
            if reduceMotion {
                #expect(incoming.allSatisfy { abs($0 - on) < 1 })
            } else {
                #expect(try #require(incoming.first) < off + (on - off) * 0.1)
                #expect(incoming.contains { $0 > off + (on - off) * 0.1 && $0 < off + (on - off) * 0.9 })
                #expect(zip(incoming, incoming.dropFirst()).allSatisfy { $1 >= $0 - 1 })
            }

            conversation.stopReply()
            let outgoing = try sample(host, checking: checkDraft).map { brightness($0, in: crop) }
            #expect(abs(brightness(try snapshot(host), in: crop) - off) < 1)
            if reduceMotion {
                #expect(outgoing.allSatisfy { abs($0 - off) < 1 })
            } else {
                #expect(try #require(outgoing.first) > off + (on - off) * 0.9)
                #expect(outgoing.contains { $0 > off + (on - off) * 0.1 && $0 < off + (on - off) * 0.9 })
                #expect(zip(outgoing, outgoing.dropFirst()).allSatisfy { $1 <= $0 + 1 })
            }
        }
    }

    private func draftEditor(in view: NSView) -> DraftTextView? {
        if let editor = view as? DraftTextView { return editor }
        return view.subviews.lazy.compactMap { draftEditor(in: $0) }.first
    }

    private func sample(_ view: NSView, checking check: () throws -> Void) throws -> [NSBitmapImageRep] {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        var images: [NSBitmapImageRep] = []
        repeat {
            images.append(try snapshot(view))
            try check()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.008))
        } while ProcessInfo.processInfo.systemUptime < deadline
        return images
    }

    private func snapshot(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
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

    private func brightness(_ image: NSBitmapImageRep, in rect: CGRect) -> Double {
        var total = 0.0
        for y in max(0, Int(rect.minY * 2))..<min(image.pixelsHigh, Int(rect.maxY * 2)) {
            for x in max(0, Int(rect.minX * 2))..<min(image.pixelsWide, Int(rect.maxX * 2)) {
                guard let color = image.colorAt(x: x, y: y) else { continue }
                total += (color.redComponent + color.greenComponent + color.blueComponent) * color.alphaComponent
            }
        }
        return total
    }
}
