import CoreGraphics
import Testing
@testable import Pocket

struct AvatarMouthTests {
    @Test func mouthsRemainReadableAndDistinctAtEveryDisplaySize() throws {
        let native = try #require(AvatarRenderer.image(for: AvatarAppearance()))
        for extent in [native.width] + AvatarAppearance.Size.allCases.map(\.rawValue) {
            var poses: [Set<Int>] = []
            for mouth in AvatarRenderer.Mouth.allCases {
                let image = try #require(AvatarRenderer.image(for: AvatarAppearance(), mouth: mouth))
                let ink = try pixels(image, extent: extent).mouthInk
                #expect(!ink.isEmpty, "\(mouth), \(extent)px: mouth must remain visible")
                #expect(!poses.contains(ink), "\(mouth), \(extent)px: mouth poses must remain distinct")
                poses.append(ink)
            }
        }
    }

    @Test(arguments: AvatarRenderer.Mouth.allCases)
    func mouthInkIsPaletteIndependent(_ mouth: AvatarRenderer.Mouth) throws {
        let baseline = try pixels(#require(AvatarRenderer.image(for: AvatarAppearance(), mouth: mouth))).mouthInk
        for palette in AvatarAppearance.Palette.allCases {
            var appearance = AvatarAppearance()
            appearance.palette = palette
            #expect(try pixels(#require(AvatarRenderer.image(for: appearance, mouth: mouth))).mouthInk == baseline)
        }
    }

    @Test(arguments: AvatarRenderer.Mouth.allCases)
    func mouthInkDoesNotDependOnFaceEyesOrHeadwear(_ mouth: AvatarRenderer.Mouth) throws {
        let baseline = try pixels(#require(AvatarRenderer.image(for: AvatarAppearance(), mouth: mouth))).mouthInk
        var fixtures: [(AvatarAppearance, AvatarRenderer.Eyes)] = []
        for face in AvatarAppearance.Face.allCases {
            var appearance = AvatarAppearance()
            appearance.face = face
            fixtures.append((appearance, .natural))
        }
        fixtures += AvatarRenderer.Eyes.allCases.map { (AvatarAppearance(), $0) }
        for headwear in AvatarAppearance.Headwear.allCases {
            var appearance = AvatarAppearance()
            appearance.headwear = headwear
            fixtures.append((appearance, .natural))
        }
        var customized = AvatarAppearance()
        customized.face = .glasses
        customized.headwear = .bandana
        fixtures.append((customized, .blink))
        for (appearance, eyes) in fixtures {
            let image = try #require(AvatarRenderer.image(for: appearance, mouth: mouth, eyes: eyes))
            #expect(try pixels(image).mouthInk == baseline, "\(mouth), \(appearance), \(eyes)")
        }
    }

    @Test func changingMouthLeavesTheRestOfTheArtworkUntouched() throws {
        for palette in AvatarAppearance.Palette.allCases {
            var appearance = AvatarAppearance()
            appearance.palette = palette
            let baseline = try pixels(#require(AvatarRenderer.image(for: appearance))).outsideMouth
            for mouth in AvatarRenderer.Mouth.allCases {
                let image = try #require(AvatarRenderer.image(for: appearance, mouth: mouth))
                #expect(try pixels(image).outsideMouth == baseline)
            }
        }
    }

    private struct Pixels {
        let bytes: [UInt8]
        let extent: Int

        // A generous lower-center face region, excluding eyes and headwear.
        func isMouth(x: Int, y: Int) -> Bool {
            (0.4..<0.6).contains(Double(x) / Double(extent))
                && (0.72..<0.86).contains(Double(y) / Double(extent))
        }

        var mouthInk: Set<Int> {
            var ink: Set<Int> = []
            for y in 0..<extent {
                for x in 0..<extent where isMouth(x: x, y: y) {
                    let i = (y * extent + x) * 4
                    if bytes[i] == 32 && bytes[i + 1] == 39 && bytes[i + 2] == 31 && bytes[i + 3] == 255 {
                        ink.insert(y * extent + x)
                    }
                }
            }
            return ink
        }

        var outsideMouth: [UInt8] {
            var result: [UInt8] = []
            for y in 0..<extent {
                for x in 0..<extent where !isMouth(x: x, y: y) {
                    let i = (y * extent + x) * 4
                    result.append(contentsOf: bytes[i..<i + 4])
                }
            }
            return result
        }
    }

    // Normalize only through CGImage, without depending on renderer storage or helpers.
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
