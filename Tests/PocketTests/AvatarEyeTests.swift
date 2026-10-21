import CoreGraphics
import Testing
@testable import Pocket

struct AvatarEyeTests {
    @Test(arguments: AvatarAppearance.Face.allCases, AvatarRenderer.Eyes.allCases)
    func eyesRemainReadableAtEveryDisplaySize(
        _ face: AvatarAppearance.Face, _ eyes: AvatarRenderer.Eyes
    ) throws {
        var appearance = AvatarAppearance()
        appearance.face = face
        let image = try #require(AvatarRenderer.image(for: appearance, eyes: eyes))
        for extent in [image.width] + AvatarAppearance.Size.allCases.map(\.rawValue) {
            let artwork = try pixels(image, extent: extent)
            let ink = artwork.coverage(of: 0x20271f)
            let whites = artwork.coverage(of: appearance.palette.colors.light)
            let label = "\(face), \(eyes), \(extent)px"
            for side in [0.20..<0.50, 0.50..<0.80] {
                #expect(!artwork.inRegion(ink, x: side).isEmpty, "\(label): both eyes must remain readable")
                if [.wide, .mellow].contains(face) && eyes != .blink {
                    #expect(!artwork.inRegion(whites, x: side).isEmpty, "\(label): open eyes retain tinted whites")
                }
            }
            if ![.wide, .mellow].contains(face) || eyes == .blink {
                #expect(whites.isEmpty, "\(label): no filled lenses or whites on closed lids")
            }
        }
    }

    @Test func eyeInkAndWhiteMasksArePaletteIndependent() throws {
        let fixtures = AvatarAppearance.Face.allCases.map { ($0, AvatarRenderer.Eyes.natural) }
            + [(.wide, .glance), (.mellow, .blink), (.glasses, .blink)]
        for (face, eyes) in fixtures {
            var appearance = AvatarAppearance()
            appearance.face = face
            let baseline = try pixels(#require(AvatarRenderer.image(for: appearance, eyes: eyes)))
            let ink = baseline.coverage(of: 0x20271f)
            let whites = baseline.coverage(of: appearance.palette.colors.light)
            for palette in AvatarAppearance.Palette.allCases {
                appearance.palette = palette
                let artwork = try pixels(#require(AvatarRenderer.image(for: appearance, eyes: eyes)))
                #expect(artwork.coverage(of: 0x20271f) == ink, "\(face), \(eyes), \(palette)")
                #expect(artwork.coverage(of: palette.colors.light) == whites, "\(face), \(eyes), \(palette)")
            }
        }
    }

    @Test(arguments: [AvatarAppearance.Face.wide, .mellow])
    func openEyesMovePupilsWithoutMovingTheWhites(_ face: AvatarAppearance.Face) throws {
        var appearance = AvatarAppearance()
        appearance.face = face
        let palette = appearance.palette
        let natural = try #require(AvatarRenderer.image(for: appearance))
        let glance = try #require(AvatarRenderer.image(for: appearance, eyes: .glance))
        for extent in [natural.width] + AvatarAppearance.Size.allCases.map(\.rawValue) {
            let straight = try pixels(natural, extent: extent)
            let looking = try pixels(glance, extent: extent)
            let straightInk = straight.coverage(of: 0x20271f)
            let lookingInk = looking.coverage(of: 0x20271f)
            let straightWhites = straight.coverage(of: palette.colors.light)
            let lookingWhites = looking.coverage(of: palette.colors.light)
            #expect(straightInk.union(straightWhites) == lookingInk.union(lookingWhites),
                    "\(extent)px: the outer white silhouette stays still")
            #expect(straightInk != lookingInk, "\(extent)px: glance remains visible")
            for side in [0.20..<0.50, 0.50..<0.80] {
                let before = straight.inRegion(straightInk, x: side)
                let after = looking.inRegion(lookingInk, x: side)
                // At S, nearest-neighbor sampling can hold one pupil on the same display column.
                #expect(try meanX(after, extent: extent) >= meanX(before, extent: extent))
                if extent == natural.width {
                    #expect(try meanX(after, extent: extent) > meanX(before, extent: extent))
                }
                #expect(!straight.inRegion(straightWhites.intersection(lookingWhites), x: side).isEmpty)
                if face == .mellow {
                    let top = try #require(before.map { $0 / extent }.min())
                    let lid = Set(before.filter { $0 / extent == top })
                    #expect(lid == Set(after.filter { $0 / extent == top }),
                            "\(extent)px: relaxed upper lids stay fixed during a glance")
                    #expect(lid.count >= extent / 20, "The mellow lid must remain a readable horizontal stroke")
                    #expect(straight.inRegion(straightWhites, x: side).allSatisfy { $0 / extent > top },
                            "Mellow whites stay below the relaxed lid")
                }
            }
        }
    }

    @Test func faceChoicesRemainDistinctAtEveryDisplaySize() throws {
        for size in AvatarAppearance.Size.allCases {
            var rendered: [[UInt8]] = []
            for face in AvatarAppearance.Face.allCases {
                var appearance = AvatarAppearance()
                appearance.face = face
                let artwork = try pixels(#require(AvatarRenderer.image(for: appearance)), extent: size.rawValue)
                let eyes = artwork.region(x: 0.25..<0.74, y: 0.49..<0.72)
                #expect(!rendered.contains(eyes), "\(size), \(face): face choices must remain distinguishable")
                rendered.append(eyes)
            }
        }
    }

    @Test func glassesKeepSkinVisibleBetweenPupilsAndRims() throws {
        var appearance = AvatarAppearance()
        for eyes in AvatarRenderer.Eyes.allCases {
            appearance.face = .dots
            let bareImage = try #require(AvatarRenderer.image(for: appearance, eyes: eyes))
            appearance.face = .glasses
            let glassesImage = try #require(AvatarRenderer.image(for: appearance, eyes: eyes))
            let glasses = try pixels(glassesImage)
            // Inspect row topology, not exact pixel counts. At native size both rims are
            // sampled; a one-cell outer rim can fall between display pixels at smaller sizes.
            for extent in [glasses.extent] + AvatarAppearance.Size.allCases.map(\.rawValue) {
                let displayed = try pixels(glassesImage, extent: extent)
                let bare = try pixels(bareImage, extent: extent)
                let displayedInk = displayed.coverage(of: 0x20271f)
                for (lens, center) in [(0.25..<0.48, 0.33..<0.43), (0.51..<0.74, 0.59..<0.69)] {
                    let rows = Int(Double(extent) * 0.56)..<Int(Double(extent) * 0.65)
                    let pupil = displayed.inRegion(displayedInk, x: center)
                    // Small displays can miss one thin outer rim, but must still show
                    // a pupil/lid AND a separate rim, not merely two empty frames.
                    let minimumRuns = extent == glasses.extent || extent == AvatarAppearance.Size.large.rawValue ? 3 : 2
                    #expect(rows.contains { row in
                        pupil.contains { $0 / extent == row }
                            && displayed.inkRuns(displayedInk, x: lens, y: row) >= minimumRuns
                    }, "\(eyes), \(extent)px: visible skin gap between pupil/lid and rim")
                }
                // These inner-lens gaps contain neither dot eyes nor glasses strokes.
                for gap in [0.30..<0.32, 0.56..<0.58] {
                    let skin = displayed.region(x: gap, y: 0.575..<0.625)
                    #expect(!skin.isEmpty)
                    #expect(skin == bare.region(x: gap, y: 0.575..<0.625),
                            "\(eyes), \(extent)px: transparent lenses must expose unchanged skin")
                }
            }
        }
    }

    @Test(arguments: AvatarAppearance.Face.allCases)
    func blinkingAndGlancingLeaveHeadwearAndMouthUntouched(_ face: AvatarAppearance.Face) throws {
        var appearance = AvatarAppearance()
        appearance.face = face
        appearance.headwear = .none
        let unobstructed = try AvatarRenderer.Eyes.allCases.map { eyes in
            (eyes, try pixels(#require(AvatarRenderer.image(for: appearance, eyes: eyes))))
        }
        // Cover each axis separately, plus customized face/headwear/mouth interactions.
        var fixtures: [(AvatarAppearance.Headwear, AvatarRenderer.Mouth)] = [(.none, .resting)]
        if face == .glasses {
            fixtures += AvatarAppearance.Headwear.allCases.map { ($0, .resting) }
            fixtures += [(.none, .small), (.none, .open)]
        } else if face == .mellow {
            fixtures += [(.bandana, .open), (.orbit, .small)]
        }
        for (headwear, mouth) in fixtures {
            appearance.headwear = headwear
            let natural = try pixels(#require(AvatarRenderer.image(for: appearance, mouth: mouth)))
            let bareNatural = try #require(unobstructed.first { $0.0 == .natural }?.1)
            for side in [0.25..<0.48, 0.51..<0.735] {
                #expect(natural.region(x: side, y: 0.49..<0.72) == bareNatural.region(x: side, y: 0.49..<0.72),
                        "\(face), \(headwear): headwear must not obscure eyes")
            }
            for eyes in [AvatarRenderer.Eyes.glance, .blink] {
                let posed = try pixels(#require(AvatarRenderer.image(for: appearance, mouth: mouth, eyes: eyes)))
                #expect(posed.outsideEyes == natural.outsideEyes, "\(face), \(headwear), \(mouth), \(eyes)")
                let staticGaze = eyes == .glance && [.happy, .dashes].contains(face)
                #expect((posed.coverage(of: 0x20271f) == natural.coverage(of: 0x20271f)) == staticGaze,
                        "\(face), \(eyes): closed expressions do not track gaze, but every face blinks")
                let bare = try #require(unobstructed.first { $0.0 == eyes }?.1)
                // Keep the right-side bandana trim outside the actual eye/lens rectangles.
                // Its light dither is headwear, not an eye white.
                for side in [0.25..<0.48, 0.51..<0.735] {
                    #expect(posed.region(x: side, y: 0.49..<0.72) == bare.region(x: side, y: 0.49..<0.72),
                            "\(face), \(headwear), \(eyes): eyes stay unobstructed")
                }
                if face == .glasses && eyes == .blink {
                    // Exclude the pupil/lid band; frames and bridge survive the blink unchanged.
                    #expect(posed.region(x: 0.20..<0.80, y: 0.45..<0.56)
                            == natural.region(x: 0.20..<0.80, y: 0.45..<0.56))
                    #expect(posed.region(x: 0.20..<0.80, y: 0.65..<0.72)
                            == natural.region(x: 0.20..<0.80, y: 0.65..<0.72))
                }
            }
        }
    }

    private struct Pixels {
        let bytes: [UInt8]
        let extent: Int

        func isEye(x: Int, y: Int) -> Bool {
            (0.20..<0.80).contains(Double(x) / Double(extent))
                // Include the full soft-square rims, below the usual 0.70 eye band.
                && (0.45..<0.72).contains(Double(y) / Double(extent))
        }

        func coverage(of color: UInt32) -> Set<Int> {
            var result: Set<Int> = []
            for y in 0..<extent {
                for x in 0..<extent where isEye(x: x, y: y) {
                    let i = (y * extent + x) * 4
                    if bytes[i] == UInt8((color >> 16) & 0xff)
                        && bytes[i + 1] == UInt8((color >> 8) & 0xff)
                        && bytes[i + 2] == UInt8(color & 0xff) && bytes[i + 3] == 255 {
                        result.insert(y * extent + x)
                    }
                }
            }
            return result
        }

        func inRegion(_ coverage: Set<Int>, x: Range<Double>) -> Set<Int> {
            Set(coverage.filter { x.contains(Double($0 % extent) / Double(extent)) })
        }

        func region(x: Range<Double>, y: Range<Double>) -> [UInt8] {
            var result: [UInt8] = []
            for row in 0..<extent where y.contains(Double(row) / Double(extent)) {
                for column in 0..<extent where x.contains(Double(column) / Double(extent)) {
                    let i = (row * extent + column) * 4
                    result.append(contentsOf: bytes[i..<i + 4])
                }
            }
            return result
        }

        func inkRuns(_ ink: Set<Int>, x: Range<Double>, y: Int) -> Int {
            var runs = 0
            var wasInk = false
            for column in 0..<extent where x.contains(Double(column) / Double(extent)) {
                let isInk = ink.contains(y * extent + column)
                if isInk && !wasInk { runs += 1 }
                wasInk = isInk
            }
            return runs
        }

        var outsideEyes: [UInt8] {
            var result: [UInt8] = []
            for y in 0..<extent {
                for x in 0..<extent where !isEye(x: x, y: y) {
                    let i = (y * extent + x) * 4
                    result.append(contentsOf: bytes[i..<i + 4])
                }
            }
            return result
        }
    }

    private func meanX(_ coverage: Set<Int>, extent: Int) throws -> Double {
        try #require(!coverage.isEmpty)
        return coverage.reduce(0.0) { $0 + Double($1 % extent) } / Double(coverage.count)
    }

    // Normalize through the public CGImage, using the same nearest-neighbor scaling as AvatarView.
    private func pixels(_ image: CGImage, extent: Int? = nil) throws -> Pixels {
        let extent = extent ?? image.width
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: extent, height: extent, bitsPerComponent: 8, bytesPerRow: extent * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: extent, height: extent))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return Pixels(bytes: Array(UnsafeBufferPointer(start: data, count: extent * extent * 4)), extent: extent)
    }
}
