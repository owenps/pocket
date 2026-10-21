import AppKit
import Observation

/// A quiet unread mark, independent of conversation read receipts.
@MainActor
final class MenuBarStatus {
    private let state: PanelState
    private let onChange: (MenuBarStatus) -> Void
    private(set) var showsUnreadReply = false

    init(state: PanelState, onChange: @escaping (MenuBarStatus) -> Void = { _ in }) {
        self.state = state
        self.onChange = onChange
        observe()
    }

    var image: NSImage { showsUnreadReply ? Self.unreadImage : Self.baseImage }
    var toolTip: String {
        "Pocket — local simulation, assistant not connected, no network"
            + (showsUnreadReply ? " — unread reply" : "")
    }
    var accessibilityLabel: String {
        "Pocket, local simulation, assistant not connected, no network"
            + (showsUnreadReply ? ", unread reply" : "")
    }

    private func observe() {
        let flags = withObservationTracking {
            (state.conversation.hasUnreadReply, state.isExpanded)
        } onChange: { [weak self] in
            // Observation fires before the write; rearm using the settled values.
            Task { @MainActor [weak self] in self?.observe() }
        }
        showsUnreadReply = flags.0 && !flags.1
        onChange(self)
    }

    private static let baseImage = makeImage(named: "capsule")
    private static let unreadImage = makeImage(named: "capsule-unread")

    private static func makeImage(named name: String) -> NSImage {
        // Packaged apps carry these PDFs directly in Contents/Resources.
        let url = Bundle.main.url(forResource: name, withExtension: "pdf")
            ?? Bundle.module.url(forResource: name, withExtension: "pdf")
        guard let url, let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing menu-bar resource: \(name).pdf")
        }
        image.size = NSSize(width: 28, height: 18)
        image.isTemplate = true
        return image
    }
}
