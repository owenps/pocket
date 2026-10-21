import AppKit
import Foundation
import PocketTestSupport
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct UserNameTests {
    @Test func nameDefaultsToEmptyPersistsAndCanBeCleared() throws {
        try withTestDefaults { defaults in
            @MainActor func makeState() -> PanelState {
                PanelState(
                    conversation: ConversationSession(backend: ControlledAssistantBackend(), defaults: defaults),
                    defaults: defaults
                )
            }

            let state = makeState()
            #expect(state.userName.isEmpty)
            state.userName = "Owen"
            #expect(makeState().userName == "Owen")
            state.userName = ""
            #expect(makeState().userName.isEmpty)
        }
    }

    @Test func nameChangesPreserveDraftAndReachTheNextOpeningGreeting() throws {
        try withTestDefaults { defaults in
            _ = NSApplication.shared
            let state = PanelState(
                conversation: ConversationSession(backend: ControlledAssistantBackend(), defaults: defaults),
                defaults: defaults
            )
            state.userName = "Owen"
            state.conversation.draft = "Keep my draft"
            state.openPanel()
            state.expansionProgress = 1
            state.surfaceRect = CGRect(origin: .zero, size: state.expandedSize)
            let fixture = OffscreenHost(PanelView(
                state: state, expand: { state.openPanel() }, collapse: { state.closePanel() },
                editorHeightChanged: { _ in }, submit: { state.submitDraft() }
            ), size: state.surfaceRect.size)
            defer { fixture.close() }
            let host = fixture.view
            try waitForLayout(host) { self.editor(in: host)?.userName == "Owen" }
            let editor = try #require(self.editor(in: host))
            let greeting = editor.placeholder
            let selection = NSRange(location: 2, length: 4)
            editor.setSelectedRange(selection)

            state.userName = "Alex"
            try waitForLayout(host) { editor.userName == "Alex" }
            #expect(self.editor(in: host) === editor)
            #expect(editor.placeholder == greeting)
            #expect(editor.string == "Keep my draft")
            #expect(editor.selectedRange() == selection)

            state.closePanel()
            try waitForLayout(host) { !editor.isEditable }
            state.openPanel()
            try waitForLayout(host) { editor.isEditable && editor.placeholder != greeting }
            let greetings = OpeningGreetings.messages(userName: "Alex", hour: Calendar.current.component(.hour, from: .now))
            #expect(greetings.contains(editor.placeholder))
            #expect(!editor.placeholder.contains("Owen"))
            #expect(editor.string == "Keep my draft")
            #expect(editor.selectedRange() == selection)
        }
    }

    private func editor(in view: NSView) -> DraftTextView? {
        if let editor = view as? DraftTextView { return editor }
        return view.subviews.lazy.compactMap { editor(in: $0) }.first
    }

    private func waitForLayout(_ host: NSView, until condition: () -> Bool) throws {
        try NativeUITestSupport.wait {
            host.layoutSubtreeIfNeeded()
            return condition()
        }
    }

}
