import AppKit
import PocketTestSupport
import SwiftUI
import Testing
@testable import Pocket

extension PanelViewTests {
    @Test(arguments: [false, true])
    func stopVisibilityTracksRepliesWithoutMovingOrReplacingTheDraft(reduceMotion: Bool) async throws {
        NativeAccessibility.enable()
        let name = "StopButtonTests.\(UUID().uuidString)"
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
        ).environment(\._accessibilityReduceMotion, reduceMotion)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }, size: state.expandedSize)
        defer { fixture.close() }
        let host = fixture.view
        var lastRendering = "not sampled"
        func waitForRendering(_ phase: String, until condition: () throws -> Bool) async throws {
            do {
                try await AsyncTestSupport.wait(until: condition)
            } catch {
                throw StopRenderingFailure(description:
                    "\(phase), reduceMotion=\(reduceMotion), busy=\(conversation.isBusy): \(error); \(lastRendering)"
                )
            }
        }
        try await waitForRendering("mount draft editor") {
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

        // Offscreen bitmaps verify rendered visibility, not compositor fade frames.
        // Exercise the first response from an idle mount, then a subsequent one.
        for reply in 1...2 {
            let idle = try snapshot(host)
            #expect(state.submitDraft())
            conversation.draft = "Retained next draft"
            var crop = CGRect.zero
            try await waitForRendering("show Stop for reply \(reply)") {
                host.layoutSubtreeIfNeeded()
                try checkDraft()
                guard let stop = accessibility.descendant(identifier: "stop-reply") else {
                    lastRendering = "Stop accessibility element missing"
                    return false
                }
                crop = host.convert(fixture.window.convertFromScreen(stop.frame), from: nil)
                lastRendering = "crop=\(crop), bounds=\(host.bounds)"
                guard crop.width > 0, crop.height > 0, host.bounds.contains(crop) else { return false }
                let off = brightness(idle, in: crop)
                let on = try brightness(snapshot(host), in: crop)
                lastRendering += ", off=\(off), on=\(on)"
                return on > off + 100
            }
            let off = brightness(idle, in: crop)
            #expect(off < 1)

            conversation.stopReply()
            try await waitForRendering("hide Stop for reply \(reply)") {
                host.layoutSubtreeIfNeeded()
                try checkDraft()
                let hidden = try brightness(snapshot(host), in: crop)
                lastRendering = "crop=\(crop), off=\(off), hidden=\(hidden)"
                return abs(hidden - off) < 1
            }
        }
    }

    private struct StopRenderingFailure: Error, CustomStringConvertible {
        let description: String
    }

    private func draftEditor(in view: NSView) -> DraftTextView? {
        if let editor = view as? DraftTextView { return editor }
        return view.subviews.lazy.compactMap { draftEditor(in: $0) }.first
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
