import AppKit
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct FontSizePreviewTests {
    nonisolated static let minimumTestedWidth: CGFloat = 380

    @Test(arguments: [ColorScheme.light, .dark])
    func changingFontSizeKeepsThePreviewStableAndItsTextInsideTheSurface(scheme: ColorScheme) throws {
        let small = try render(size: PanelState.fontSizeRange.lowerBound, scheme: scheme)
        let large = try render(size: PanelState.fontSizeRange.upperBound, scheme: scheme)
        #expect(small.size == large.size)
        #expect(large.text.height > small.text.height)
        for sample in [small, large] {
            #expect(!sample.surface.isNull && !sample.text.isNull)
            #expect(sample.surface.height > sample.size.height / 2)
            #expect(sample.surface.insetBy(dx: 3, dy: 3).contains(sample.text))
        }
    }

    private func render(size: Double, scheme: ColorScheme) throws
        -> (size: CGSize, surface: CGRect, text: CGRect) {
        let renderer = ImageRenderer(content: FontSizePreview(fontSize: size)
            .frame(width: Self.minimumTestedWidth)
            .environment(\.colorScheme, scheme))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        var surface = CGRect.null
        var text = CGRect.null
        for y in 0..<image.height {
            var blackPixels = 0
            var blackRow = CGRect.null
            for x in 0..<image.width {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.95 else { continue }
                let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                if channels.allSatisfy({ $0 < 0.05 }) {
                    blackPixels += 1
                    blackRow = blackRow.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
                if channels.allSatisfy({ $0 > 0.95 }) {
                    text = text.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
            // Broad black rows identify the actual preview surface, excluding
            // the small caption. No copy, padding or fixed-height constants.
            if blackPixels > image.width / 2 {
                surface = surface.union(blackRow)
            }
        }
        return (CGSize(width: image.width, height: image.height), surface, text)
    }
}
