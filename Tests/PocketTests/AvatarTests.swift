import AppKit
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct AvatarTests {
    @Test func defaultsMatchTheApprovedDitherRambleHead() throws {
        let appearance = AvatarAppearance()
        #expect(appearance.palette == .campfire)
        #expect(appearance.headwear == .none)
        #expect(appearance.face == .dots)
        #expect(appearance.size == .small)
        try withTestDefaults { defaults in
            #expect(makeState(defaults).avatar == appearance)
        }
    }

    @Test func everyChoicePersistsThroughNestedMutationAndStateRecreation() throws {
        try withTestDefaults { defaults in
            let state = makeState(defaults)
            state.avatar = customizedAppearance()
            #expect(makeState(defaults).avatar == state.avatar)
            try checkChoices(AvatarAppearance.Palette.allCases, at: \.palette, state: state, defaults: defaults)
            try checkChoices(AvatarAppearance.Headwear.allCases, at: \.headwear, state: state, defaults: defaults)
            try checkChoices(AvatarAppearance.Face.allCases, at: \.face, state: state, defaults: defaults)
            try checkChoices(AvatarAppearance.Size.allCases, at: \.size, state: state, defaults: defaults)
        }
    }

    @Test func partialAndInvalidFieldsRecoverIndependentlyWithoutLosingValidChoices() throws {
        try withTestDefaults { defaults in
            let valid = customizedAppearance()
            let data = try JSONEncoder().encode(valid)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let fields: [(String, (inout AvatarAppearance) -> Void)] = [
                ("palette", { $0.palette = .campfire }),
                ("headwear", { $0.headwear = .none }),
                ("face", { $0.face = .dots }),
                ("size", { $0.size = .small }),
            ]
            for (fieldIndex, entry) in fields.enumerated() {
                let (field, reset) = entry
                var expected = valid
                reset(&expected)
                // Missing, future enum value, null, and wrong JSON types.
                let invalidValues: [Any?] = [nil, "future-choice", NSNull(), 999, [], ["unexpected": true]]
                for (invalidIndex, invalid) in invalidValues.enumerated() {
                    var saved = object
                    saved[field] = invalid
                    saved["futureOption"] = "ignored"
                    let partial = try JSONSerialization.data(withJSONObject: saved)
                    #expect(try JSONDecoder().decode(AvatarAppearance.self, from: partial) == expected)
                    // Persistence uses representative malformed fixtures; decoding covers the full matrix.
                    if invalidIndex == fieldIndex {
                        defaults.set(partial, forKey: "avatarAppearance")
                        #expect(makeState(defaults).avatar == expected)
                    }
                }
            }
            defaults.set(Data("{}".utf8), forKey: "avatarAppearance")
            #expect(makeState(defaults).avatar == AvatarAppearance())
        }
    }

    @Test func corruptOrNonObjectSavedAppearanceUsesDefaults() throws {
        try withTestDefaults { defaults in
            for json in ["", "{broken", "[]", "null", "42", "\"not an appearance\""] {
                defaults.set(Data(json.utf8), forKey: "avatarAppearance")
                #expect(makeState(defaults).avatar == AvatarAppearance())
            }
            defaults.set("not encoded data", forKey: "avatarAppearance")
            #expect(makeState(defaults).avatar == AvatarAppearance())
        }
    }

    @Test func buddyVisibilityPersistsWithoutChangingAppearance() throws {
        try withTestDefaults { defaults in
            let state = makeState(defaults)
            #expect(state.showBuddy)
            let appearance = customizedAppearance()
            state.avatar = appearance
            state.showBuddy = false
            let recreated = makeState(defaults)
            #expect(!recreated.showBuddy)
            #expect(recreated.avatar == appearance)
            recreated.showBuddy = true
            #expect(makeState(defaults).showBuddy)
            #expect(makeState(defaults).avatar == appearance)
            recreated.showBuddy = false
            recreated.avatar = AvatarAppearance()
            #expect(!makeState(defaults).showBuddy)
        }
    }

    @Test func legacyChoicesKeepSupportedValuesAndMigrateSleepyToMellow() throws {
        #expect(AvatarAppearance.Face(rawValue: "sleepy") == nil)
        let fixtures: [(String, AvatarAppearance.Headwear, AvatarAppearance.Face)] = [
            (#"{"palette":"glacier","headwear":"beanie","face":"dots","size":56,"framing":"body","character":"pip","material":"ascii"}"#, .beanie, .dots),
            (#"{"palette":"glacier","headwear":"none","face":"sleepy","size":56}"#, .none, .mellow),
            (#"{"palette":"glacier","headwear":"cap","face":"wide","size":56}"#, .cap, .wide),
            (#"{"palette":"glacier","headwear":"sprout","face":"glasses","size":56}"#, .sprout, .glasses),
            (#"{"palette":"glacier","headwear":"antenna","face":"dots","size":56}"#, .antenna, .dots),
        ]
        try withTestDefaults { defaults in
            for (json, headwear, face) in fixtures {
                let data = Data(json.utf8)
                var expected = AvatarAppearance()
                expected.palette = .glacier
                expected.headwear = headwear
                expected.face = face
                expected.size = .large
                #expect(try JSONDecoder().decode(AvatarAppearance.self, from: data) == expected)
                defaults.set(data, forKey: "avatarAppearance")
                let restored = makeState(defaults)
                #expect(restored.avatar == expected)
                restored.avatar.size = .medium
                let saved = try #require(defaults.data(forKey: "avatarAppearance"))
                let original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                let updated = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
                #expect(updated["headwear"] as? String == original["headwear"] as? String)
                #expect(updated["face"] as? String == expected.face.rawValue)
                #expect(makeState(defaults).avatar == restored.avatar)
            }
        }
    }

    @Test func rendererProducesVisibleTransparentDeterministicArtwork() throws {
        for appearance in [AvatarAppearance(), customizedAppearance()] {
            let image = try #require(AvatarRenderer.image(for: appearance))
            #expect(image.width > 0)
            #expect(image.width == image.height)
            let first = try pixels(image)
            let second = try pixels(#require(AvatarRenderer.image(for: appearance)))
            #expect(first == second)
            let alphas = stride(from: 3, to: first.count, by: 4).map { first[$0] }
            let visible = alphas.filter { $0 > 0 }.count
            #expect(visible > alphas.count / 100)
            #expect(alphas.filter { $0 == 0 }.count > alphas.count / 100)
            #expect(alphas.contains { $0 == 255 })
        }
    }

    @Test func customizationChoicesMeaningfullyChangeTheRenderedArtwork() throws {
        let baseline = AvatarAppearance()
        let image = try #require(AvatarRenderer.image(for: baseline))
        let original = try pixels(image)
        let variations = alternatives(AvatarAppearance.Palette.allCases, at: \.palette)
            + alternatives(AvatarAppearance.Headwear.allCases, at: \.headwear)
            + alternatives(AvatarAppearance.Face.allCases, at: \.face)
        for appearance in variations {
            let changedImage = try #require(AvatarRenderer.image(for: appearance))
            #expect(changedImage.width == image.width)
            #expect(changedImage.height == image.height)
            let changed = try pixels(changedImage)
            try #require(changed.count == original.count)
            let changedPixels = stride(from: 0, to: original.count, by: 4).filter { offset in
                (0..<4).contains { original[offset + $0] != changed[offset + $0] }
            }.count
            // Reject a no-op or a token pixel change, without prescribing the drawing algorithm.
            #expect(changedPixels > image.width * image.height / 1_000, "No meaningful change for \(appearance)")
        }
    }

    @Test func headwearStaysDistinctAndPromotedShapesRemainReadableAtDisplaySizes() throws {
        for size in AvatarAppearance.Size.allCases {
            let extent = size.rawValue
            var artwork: [AvatarAppearance.Headwear: [UInt8]] = [:]
            for headwear in AvatarAppearance.Headwear.allCases {
                var appearance = AvatarAppearance()
                appearance.headwear = headwear
                artwork[headwear] = try pixels(#require(AvatarRenderer.image(for: appearance)), extent: extent)
            }
            let bare = try #require(artwork[.none])
            for (index, headwear) in AvatarAppearance.Headwear.allCases.enumerated() {
                let actual = try #require(artwork[headwear])
                for other in AvatarAppearance.Headwear.allCases.dropFirst(index + 1) {
                    #expect(actual != artwork[other], "\(size): \(headwear) and \(other) must remain distinguishable")
                }
                if [.mushroom, .bandana, .orbit, .pebbles].contains(headwear) {
                    let changed = stride(from: 0, to: actual.count, by: 4).filter { i in
                        actual[i..<i + 4] != bare[i..<i + 4]
                    }.count
                    #expect(changed > extent * extent / 100, "\(size), \(headwear): accessory must be more than a token mark")
                    let crown = (0..<extent / 3).flatMap { y in
                        (0..<extent).map { x in actual[(y * extent + x) * 4 + 3] }
                    }
                    #expect(crown.filter { $0 == 255 }.count > extent * extent / 100,
                            "\(size), \(headwear): readable crown silhouette")
                }
            }
        }
    }

    @Test func displaySizesAreFixedSquaresAndDoNotChangeTheArtwork() throws {
        _ = NSApplication.shared
        let original = try pixels(#require(AvatarRenderer.image(for: AvatarAppearance())))
        let sizes: [(AvatarAppearance.Size, CGFloat)] = [(.small, 40), (.medium, 48), (.large, 56)]
        for (size, points) in sizes {
            var appearance = AvatarAppearance()
            appearance.size = size
            #expect(size.points == points)
            let host = NSHostingView(rootView: AvatarView(appearance: appearance))
            #expect(host.fittingSize == NSSize(width: points, height: points))
            let image = try #require(AvatarRenderer.image(for: appearance))
            #expect(image.width == image.height)
            #expect(try pixels(image) == original)
        }
        var appearance = customizedAppearance()
        appearance.size = .large
        let preview = NSHostingView(rootView: AvatarView(appearance: appearance, size: 48))
        #expect(preview.fittingSize == NSSize(width: 48, height: 48))
        let speaking = NSHostingView(rootView: AvatarView(appearance: appearance, size: 48, behavior: .speaking))
        #expect(speaking.fittingSize == preview.fittingSize)
    }

    private func customizedAppearance() -> AvatarAppearance {
        var appearance = AvatarAppearance()
        appearance.palette = .glacier
        appearance.headwear = .antenna
        appearance.face = .glasses
        appearance.size = .large
        return appearance
    }

    private func checkChoices<Value>(
        _ choices: [Value], at keyPath: WritableKeyPath<AvatarAppearance, Value>,
        state: PanelState, defaults: UserDefaults
    ) throws {
        for choice in choices {
            var expected = state.avatar
            expected[keyPath: keyPath] = choice
            state.avatar[keyPath: keyPath] = choice
            let saved = try #require(defaults.data(forKey: "avatarAppearance"))
            #expect(try JSONDecoder().decode(AvatarAppearance.self, from: saved) == expected)
            #expect(makeState(defaults).avatar == expected)
        }
    }

    private func alternatives<Value: Equatable>(
        _ choices: [Value], at keyPath: WritableKeyPath<AvatarAppearance, Value>
    ) -> [AvatarAppearance] {
        choices.filter { $0 != AvatarAppearance()[keyPath: keyPath] }.map { choice in
            var appearance = AvatarAppearance()
            appearance[keyPath: keyPath] = choice
            return appearance
        }
    }

    // Normalize through a public CGImage into RGBA; no renderer storage/layout assumptions.
    private func pixels(_ image: CGImage, extent: Int? = nil) throws -> [UInt8] {
        let extent = extent ?? image.width
        let context = try #require(CGContext(
            data: nil, width: extent, height: extent, bitsPerComponent: 8,
            bytesPerRow: extent * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: extent, height: extent))
        let data = try #require(context.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: extent * extent * 4))
    }

    private func makeState(_ defaults: UserDefaults) -> PanelState {
        PanelState(conversation: ConversationSession(backend: ControlledAssistantBackend(), defaults: defaults), defaults: defaults)
    }
}
