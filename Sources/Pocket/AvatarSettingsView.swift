import SwiftUI

struct AvatarSettingsView: View {
    @Binding var appearance: AvatarAppearance
    @Binding var showBuddy: Bool
    @State private var previewBehavior: AvatarAnimation.Behavior = .inactive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section {
            Toggle("Show buddy", isOn: $showBuddy)
                .accessibilityIdentifier("showBuddy")

            if showBuddy {
                customization
            }
        } header: {
            Text("Buddy")
        }
        .pickerStyle(.menu)
        .onChange(of: appearance) { _, _ in
            previewBehavior = showBuddy && !reduceMotion ? .preview : .inactive
        }
        .onChange(of: showBuddy) { _, shown in
            if !shown { previewBehavior = .inactive }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { previewBehavior = .inactive }
        }
        .onDisappear { previewBehavior = .inactive }
    }

    private var customization: some View {
        Group {
            preview

            HStack {
                Text("Palette")
                Spacer()
                AvatarPalettePicker(selection: $appearance.palette)
                    .fixedSize()
            }

            Picker("Headwear", selection: $appearance.headwear) {
                ForEach(AvatarAppearance.Headwear.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("avatarHeadwearPicker")

            Picker("Face", selection: $appearance.face) {
                ForEach(AvatarAppearance.Face.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("avatarFacePicker")

            Picker("Size", selection: $appearance.size) {
                ForEach(AvatarAppearance.Size.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("avatarSizePicker")

            HStack {
                Button("Surprise Me") {
                    appearance.palette = AvatarAppearance.Palette.allCases.randomElement() ?? .campfire
                    appearance.headwear = AvatarAppearance.Headwear.allCases.randomElement() ?? .none
                    appearance.face = AvatarAppearance.Face.allCases.randomElement() ?? .dots
                }
                Spacer()
                Button("Reset Appearance") { appearance = AvatarAppearance() }
                    .disabled(appearance == AvatarAppearance())
            }
        }
    }

    private var preview: some View {
        AvatarView(appearance: appearance, size: 112,
                   behavior: reduceMotion ? .inactive : previewBehavior)
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(.black, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(false)
            .accessibilityLabel("Buddy preview: \(appearance.palette.title), \(appearance.headwear.title), \(appearance.face.title)")
    }
}
