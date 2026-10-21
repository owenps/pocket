import AppKit
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct DraftEditorLayoutTests {
    @Test func shortDraftKeepsFirstLineVisibleDuringGrowthAndDeletion() throws {
        let fixture = EditorFixture(height: DraftEditor.singleLineHeight(fontSize: 13))
        defer { fixture.close() }
        let view = fixture.view
        let editor = view.editor
        editor.insertText("test", replacementRange: editor.selectedRange())
        let initialHeight = NativeTextTestSupport.height(of: editor)
        let initialTop = try firstLineTop(in: view)
        #expect(fixture.text == "test")
        #expect(fixture.window.firstResponder === editor)
        try expectFirstLine(in: view, at: initialTop)

        // Text changes immediately; IslandMotion's viewport catches up over many
        // fractional frames. The transcript is deliberately not involved.
        var previousHeight = initialHeight
        for lineCount in 2...3 {
            editor.keyDown(with: NativeTextTestSupport.keyEvent(modifiers: .shift))
            #expect(fixture.text == "test" + String(repeating: "\n", count: lineCount - 1))
            let targetHeight = NativeTextTestSupport.height(of: editor)
            #expect(targetHeight > previousHeight)
            #expect(targetHeight < 140)
            try expectFirstLine(in: view, at: initialTop)
            try resize(view, from: previousHeight, to: targetHeight, firstLineTop: initialTop)
            previousHeight = targetHeight
        }

        for lineCount in stride(from: 2, through: 1, by: -1) {
            editor.deleteBackward(nil)
            #expect(fixture.text == "test" + String(repeating: "\n", count: lineCount - 1))
            let targetHeight = NativeTextTestSupport.height(of: editor)
            #expect(targetHeight < previousHeight)
            try expectFirstLine(in: view, at: initialTop)
            try resize(view, from: previousHeight, to: targetHeight, firstLineTop: initialTop)
            previousHeight = targetHeight
        }
        #expect(previousHeight == initialHeight)
        #expect(fixture.window.firstResponder === editor)
    }

    @Test func keyboardNavigationStillScrollsDraftsAboveTheHeightCap() throws {
        let fixture = EditorFixture(height: 140)
        defer { fixture.close() }
        let view = fixture.view
        let editor = view.editor
        let text = Array(repeating: "test", count: 24).joined(separator: "\n")
        editor.insertText(text, replacementRange: editor.selectedRange())
        #expect(fixture.text == text)
        #expect(NativeTextTestSupport.height(of: editor) > 140)

        editor.keyDown(with: NativeTextTestSupport.keyEvent(code: 126, characters: "\u{f700}", modifiers: .command))
        #expect(editor.selectedRange().location == 0)
        let top = try firstLineTop(in: view)
        try expectFirstLine(in: view, at: top)

        editor.keyDown(with: NativeTextTestSupport.keyEvent(code: 125, characters: "\u{f701}", modifiers: .command))
        #expect(editor.selectedRange().location == text.utf16.count)
        #expect(editor.visibleRect.minY > 0)
        let lastGlyph = try glyphRect(for: NSRange(location: text.utf16.count - 4, length: 4), in: editor)
        #expect(editor.visibleRect.contains(lastGlyph))
        #expect(!(editor.visibleRect.contains(try glyphRect(for: NSRange(location: 0, length: 4), in: editor))))

        editor.keyDown(with: NativeTextTestSupport.keyEvent(code: 126, characters: "\u{f700}", modifiers: .command))
        #expect(editor.selectedRange().location == 0)
        try expectFirstLine(in: view, at: top)
    }

    private func resize(
        _ view: DraftEditorScrollView, from start: CGFloat, to target: CGFloat, firstLineTop: CGFloat
    ) throws {
        for fraction: CGFloat in [0.4, 1.02, 1] {
            view.setFrameSize(NSSize(width: 360, height: start + (target - start) * fraction))
            // Check the actual native frame before any subsequent layout pass.
            try expectFirstLine(in: view, at: firstLineTop)
            view.layoutSubtreeIfNeeded()
            #expect(abs(view.contentView.bounds.height - view.frame.height) < 0.5)
            try expectFirstLine(in: view, at: firstLineTop)
        }
    }

    private func expectFirstLine(in view: DraftEditorScrollView, at top: CGFloat) throws {
        let rect = try glyphRect(for: NSRange(location: 0, length: 4), in: view.editor)
        #expect(view.editor.visibleRect.contains(rect))
        #expect(abs(try firstLineTop(in: view) - top) < 0.5)
    }

    private func firstLineTop(in view: DraftEditorScrollView) throws -> CGFloat {
        let rect = try glyphRect(for: NSRange(location: 0, length: 4), in: view.editor)
        let clip = view.contentView
        let visibleGlyph = view.editor.convert(rect, to: clip)
        return clip.isFlipped
            ? visibleGlyph.minY - clip.bounds.minY
            : clip.bounds.maxY - visibleGlyph.maxY
    }

    private func glyphRect(for range: NSRange, in editor: NSTextView) throws -> NSRect {
        let manager = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return manager.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
    }
}

@MainActor
private final class EditorFixture {
    let view: DraftEditorScrollView
    let window: NSWindow
    var text = ""
    private lazy var coordinator = DraftEditor.Coordinator(text: Binding(
        get: { [unowned self] in MainActor.assumeIsolated { self.text } },
        set: { [unowned self] value in MainActor.assumeIsolated { self.text = value } }
    ))

    init(height: CGFloat) {
        view = DraftEditorScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: height))
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        window = NativeTextTestSupport.window(containing: host)
        host.addSubview(view)
        view.setFontSize(13)
        view.editor.delegate = coordinator
        view.setEditing(true, focusRequest: 1)
        view.refreshLayout()
    }

    func close() {
        view.editor.delegate = nil
        view.cancelHeightReport()
        window.contentView = nil
    }
}
