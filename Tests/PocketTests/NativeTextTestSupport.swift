import AppKit
import PocketTestSupport

@MainActor
enum NativeTextTestSupport {
    static func height(of text: NSTextView) -> CGFloat {
        let manager = text.layoutManager!
        let container = text.textContainer!
        manager.ensureLayout(for: container)
        let extra = manager.extraLineFragmentTextContainer === container ? manager.extraLineFragmentRect.maxY : 0
        return ceil(max(manager.usedRect(for: container).maxY, extra) + text.textContainerInset.height * 2)
    }

    static func keyEvent(
        code: UInt16 = 36, characters: String? = nil, modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        let characters = characters ?? (code == 48 ? "\t" : code == 76 ? "\u{3}" : "\r")
        return NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        )!
    }

    // Attach for native input/focus; never order front or run the event loop.
    static func window(containing view: NSView, shown: Bool = false) -> OffscreenTestWindow {
        _ = NSApplication.shared
        let window = OffscreenTestWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.shown = shown
        window.contentView = view
        return window
    }
}
