import AppKit
import PocketTestSupport
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct AvatarSettingsTests {
    @Test func appearanceControlsTrackPreferencesAndSaveSizeEdits() throws {
        try withSettings { state, defaults, host in
            state.conversation.draft = "An unsent thought"
            try waitForLayout(host) { swatch(.campfire, in: host)?.state == .on }

            state.avatar.palette = .glacier
            state.avatar.headwear = .sprout
            state.avatar.face = .glasses
            try waitForLayout(host) {
                swatch(.glacier, in: host)?.state == .on
                    && popup("Little sprout", in: host) != nil && popup("Glasses", in: host) != nil
            }
            #expect(swatch(.campfire, in: host)?.state == .off)
            #expect(swatch(.glacier, in: host)?.isAccessibilitySelected() == true)
            try selectSegment("L", in: host)
            try waitForLayout(host) {
                state.avatar.palette == .glacier && state.avatar.headwear == .sprout
                    && state.avatar.face == .glasses
                    && state.avatar.size == .large
            }
            let recreated = PanelState(
                conversation: ConversationSession(backend: ControlledAssistantBackend(), defaults: defaults),
                defaults: defaults
            )
            #expect(recreated.avatar == state.avatar)

            state.avatar.face = .mellow
            try waitForLayout(host) { popup("Mellow", in: host) != nil }
            state.avatar = AvatarAppearance()
            try waitForLayout(host) { state.avatar == AvatarAppearance() && swatch(.campfire, in: host)?.state == .on }
            #expect(swatch(.glacier, in: host)?.state == .off)
            state.avatar.headwear = .none
            try waitForLayout(host) { popup("None", in: host) != nil }
            #expect(state.conversation.draft == "An unsent thought")
        }
    }

    @Test func promotedAndRetainedChoicesStayVisibleAndPersistThroughLiveBindings() throws {
        try withSettings { state, defaults, host in
            state.avatar.palette = .lilac
            state.avatar.size = .large
            state.conversation.draft = "Keep my choices"
            let hats: [(AvatarAppearance.Headwear, String)] = [
                (.beanie, "Beanie"), (.none, "None"), (.cap, "Trail cap"),
                (.sprout, "Little sprout"), (.antenna, "Antenna"),
                (.mushroom, "Mushroom"), (.bandana, "Bandana"), (.orbit, "Orbit"), (.pebbles, "Pebbles"),
            ]
            let faces: [(AvatarAppearance.Face, String)] = [
                (.dots, "Dot eyes"), (.wide, "Wide-eyed"),
                (.glasses, "Glasses"), (.mellow, "Mellow"),
                (.happy, "Happy arches"), (.dashes, "Soft dashes"),
            ]
            for (headwear, title) in hats {
                let retainedFace = state.avatar.face
                state.avatar.headwear = headwear
                try waitForLayout(host) { popup(title, in: host) != nil }
                let control = try #require(popup(title, in: host))
                #expect(control.isEnabled)
                #expect(state.avatar.face == retainedFace)
                let recreated = PanelState(
                    conversation: ConversationSession(backend: ControlledAssistantBackend(), defaults: defaults),
                    defaults: defaults
                )
                #expect(recreated.avatar == state.avatar)
            }
            for (face, title) in faces {
                state.avatar.face = face
                try waitForLayout(host) { popup(title, in: host) != nil }
                let control = try #require(popup(title, in: host))
                #expect(control.isEnabled)
                #expect(popup("Soft square", in: host) == nil)
                #expect(state.avatar.headwear == .pebbles)
                let recreated = PanelState(
                    conversation: ConversationSession(backend: ControlledAssistantBackend(), defaults: defaults),
                    defaults: defaults
                )
                #expect(recreated.avatar == state.avatar)
            }
            #expect(state.avatar.palette == .lilac)
            #expect(state.avatar.size == .large)
            #expect(state.conversation.draft == "Keep my choices")
        }
    }

    @Test func hidingBuddyHidesCustomizationAndRestoresItUnchanged() throws {
        try withSettings { state, _, host in
            state.avatar.palette = .lilac
            state.avatar.headwear = .sprout
            let appearance = state.avatar
            try waitForLayout(host) { swatch(.lilac, in: host)?.state == .on }

            state.showBuddy = false
            try waitForLayout(host) { AvatarAppearance.Palette.allCases.allSatisfy { swatch($0, in: host) == nil } }
            #expect(state.avatar == appearance)
            state.showBuddy = true
            try waitForLayout(host) { swatch(.lilac, in: host)?.state == .on && popup("Little sprout", in: host) != nil }
            #expect(state.avatar == appearance)
        }
    }

    @Test func paletteSwatchesSelectWithoutChangingOtherChoices() throws {
        try withSettings { state, _, host in
            state.avatar.headwear = .antenna
            state.avatar.face = .wide
            state.avatar.size = .medium
            state.conversation.draft = "Keep this draft"
            try waitForLayout(host) {
                AvatarAppearance.Palette.allCases.allSatisfy { swatch($0, in: host) != nil }
            }
            let buttons = AvatarAppearance.Palette.allCases.compactMap { swatch($0, in: host) }
            for palette in AvatarAppearance.Palette.allCases {
                let button = try #require(swatch(palette, in: host))
                #expect(button.toolTip == palette.title)
                #expect(button.imagePosition == .imageOnly)
                #expect(button.image != nil)
                #expect(button.bounds.width >= 34 && button.bounds.height >= 34)
                #expect(button.window?.makeFirstResponder(button) == true)
                #expect(button.window?.firstResponder === button)
                button.performClick(nil)
                try waitForLayout(host) {
                    state.avatar.palette == palette && button.state == .on
                        && buttons.filter { $0.state == .on }.count == 1
                }
                for swatch in buttons {
                    #expect(swatch.isAccessibilitySelected() == (swatch === button))
                    #expect((swatch.accessibilityValue() as? String) == (swatch === button ? "Selected" : "Not selected"))
                }
                #expect(state.avatar.headwear == .antenna)
                #expect(state.avatar.face == .wide)
                #expect(state.avatar.size == .medium)
                // Clicking an already-selected swatch must not deselect it.
                button.performClick(nil)
                #expect(button.state == .on)
                #expect(state.avatar.palette == palette)
            }
            #expect(state.conversation.draft == "Keep this draft")
        }
    }

    private func swatch(_ palette: AvatarAppearance.Palette, in host: NSView) -> NSButton? {
        descendants(host).compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == "\(palette.title) palette"
        }
    }

    private func selectSegment(_ label: String, in host: NSView) throws {
        let control = try #require(descendants(host).compactMap { $0 as? NSSegmentedControl }.first { control in
            (0..<control.segmentCount).contains { control.label(forSegment: $0) == label }
        })
        let index = try #require((0..<control.segmentCount).first { control.label(forSegment: $0) == label })
        control.selectedSegment = index
        let action = try #require(control.action)
        #expect(NSApp.sendAction(action, to: control.target, from: control))
    }

    private func popup(_ title: String, in host: NSView) -> NSPopUpButton? {
        descendants(host).compactMap { $0 as? NSPopUpButton }.first { $0.title == title }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private func withSettings(_ body: (PanelState, UserDefaults, NSView) throws -> Void) throws {
        _ = NSApplication.shared
        try withTestDefaults { defaults in
            let state = PanelState(
                conversation: ConversationSession(backend: ControlledAssistantBackend(), defaults: defaults),
                defaults: defaults
            )
            let host = NSHostingView(rootView: Form {
                AvatarSettingsView(
                    appearance: Binding(get: { state.avatar }, set: { state.avatar = $0 }),
                    showBuddy: Binding(get: { state.showBuddy }, set: { state.showBuddy = $0 })
                )
            }.formStyle(.grouped))
            let window = OffscreenTestWindow(
                contentRect: CGRect(x: 0, y: 0, width: 520, height: 720),
                styleMask: [.titled, .closable], backing: .buffered, defer: true
            )
            window.contentView = host
            defer { window.contentView = nil }
            try waitForLayout(host) { !host.subviews.isEmpty }
            try body(state, defaults, host)
        }
    }

    private func waitForLayout(_ host: NSView, until condition: () -> Bool) throws {
        try NativeUITestSupport.wait {
            host.layoutSubtreeIfNeeded()
            return condition()
        }
    }
}
