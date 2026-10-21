import CoreGraphics

/// Ramble's 128-point artwork, rendered with a 64×64 Bayer dither.
enum AvatarRenderer {
    enum Mouth: CaseIterable {
        case resting, small, open
    }

    enum Eyes: CaseIterable {
        case natural, glance, blink
    }

    static func image(
        for appearance: AvatarAppearance, mouth: Mouth = .resting, eyes: Eyes = .natural
    ) -> CGImage? {
        guard let source = bitmap(128), let eyeMask = bitmap(128), let mouthMask = bitmap(128) else { return nil }
        // Bitmap rows, artwork coordinates, and the lab all run from top to bottom.
        for context in [source, eyeMask, mouthMask] {
            context.translateBy(x: 0, y: 128)
            context.scaleBy(x: 1, y: -1)
        }
        let palette = Palette(appearance.palette)
        drawSource(appearance, palette: palette, in: source)
        drawEyes(appearance.face, eyes: eyes, in: eyeMask)
        drawMouth(mouth, in: mouthMask)

        let cells = 64
        guard let sourceImage = source.makeImage(),
              let cropped = sourceImage.cropping(to: CGRect(x: 24, y: 0, width: 80, height: 80)),
              let eyeImage = eyeMask.makeImage(),
              let croppedEyes = eyeImage.cropping(to: CGRect(x: 24, y: 0, width: 80, height: 80)),
              let mouthImage = mouthMask.makeImage(),
              let croppedMouth = mouthImage.cropping(to: CGRect(x: 24, y: 0, width: 80, height: 80)),
              let sample = bitmap(cells), let eyeSample = bitmap(cells), let mouthSample = bitmap(cells),
              let output = bitmap(384) else { return nil }
        for (context, image) in [(sample, cropped), (eyeSample, croppedEyes), (mouthSample, croppedMouth)] {
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: cells, height: cells))
        }
        guard let data = sample.data?.assumingMemoryBound(to: UInt8.self),
              let eyeData = eyeSample.data?.assumingMemoryBound(to: UInt8.self),
              let mouthData = mouthSample.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        output.translateBy(x: 0, y: 384)
        output.scaleBy(x: 1, y: -1)
        let cell = CGFloat(384) / CGFloat(cells)
        let ramps = [palette.skin, palette.cloth, palette.light].map { base in
            (hue: base.hue, colors: [0.55, 0.78, 1, 1.16].map { base.shade($0) })
        }
        for y in 0..<cells {
            for x in 0..<cells {
                let i = (y * cells + x) * 4
                let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                // Geometric coverage, never palette classification or Bayer dithering.
                if mouthData[i + 3] >= 128 {
                    output.setFillColor(ink.cgColor)
                    output.fill(rect)
                    continue
                }
                let eyeAlpha = Double(eyeData[i + 3])
                if eyeAlpha >= 128 {
                    // The isolated mask contains only ink and neutral white; resolve before tinting.
                    let red = Double(eyeData[i]) * 255 / eyeAlpha
                    output.setFillColor((red < (ink.r + 255) / 2 ? ink : palette.light).cgColor)
                    output.fill(rect)
                    continue
                }
                let alpha = Double(data[i + 3])
                guard alpha >= 128 else { continue }
                // Canvas getImageData returns straight, rather than premultiplied, RGB.
                let color = Color(
                    min(255, (Double(data[i]) * 255 / alpha).rounded()),
                    min(255, (Double(data[i + 1]) * 255 / alpha).rounded()),
                    min(255, (Double(data[i + 2]) * 255 / alpha).rounded())
                )
                var chosen = ink
                if max(color.r, color.g, color.b) >= 55 {
                    let hue = color.hue
                    let ramp = ramps.min { $0.hue.distance(to: hue) < $1.hue.distance(to: hue) }!
                    let nearest = ramp.colors.enumerated().sorted {
                        let a = $0.element.distance(to: color), b = $1.element.distance(to: color)
                        return a == b ? $0.offset < $1.offset : a < b
                    }
                    chosen = nearest[0].element
                    let first = chosen.distance(to: color)
                    let total = first + nearest[1].element.distance(to: color)
                    let probability = first / (total == 0 ? 1 : total)
                    if (Double(bayer[(y % 4) * 4 + x % 4]) + 0.5) / 16 < probability {
                        chosen = nearest[1].element
                    }
                }
                output.setFillColor(chosen.cgColor)
                output.fill(rect)
            }
        }
        return output.makeImage()
    }

    private static let ink = Color(32, 39, 31)
    private static let bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

    private struct Color {
        let r: Double
        let g: Double
        let b: Double

        init(_ r: Double, _ g: Double, _ b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        init(_ hex: UInt32) {
            self.init(Double((hex >> 16) & 0xff), Double((hex >> 8) & 0xff), Double(hex & 0xff))
        }

        var cgColor: CGColor {
            CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
        }

        var hue: Color {
            let sum = r + g + b
            let divisor = sum == 0 ? 1 : sum
            return Color(r / divisor, g / divisor, b / divisor)
        }

        func shade(_ amount: Double) -> Color {
            Color(min(255, r * amount).rounded(), min(255, g * amount).rounded(), min(255, b * amount).rounded())
        }

        func distance(to other: Color) -> Double {
            let dr = r - other.r, dg = g - other.g, db = b - other.b
            return dr * dr + dg * dg + db * db
        }
    }

    private struct Palette {
        let skin: Color
        let cloth: Color
        let light: Color

        init(_ palette: AvatarAppearance.Palette) {
            let colors = palette.colors
            skin = Color(colors.skin)
            cloth = Color(colors.cloth)
            light = Color(colors.light)
        }
    }

    private static func bitmap(_ extent: Int) -> CGContext? {
        CGContext(
            data: nil, width: extent, height: extent, bitsPerComponent: 8, bytesPerRow: extent * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
    }

    private static func drawSource(
        _ appearance: AvatarAppearance, palette: Palette, in pen: CGContext
    ) {
        let skin = palette.skin, cloth = palette.cloth, light = palette.light
        ellipse(33, 51, 6, 8, skin, in: pen)
        ellipse(95, 51, 6, 8, skin, in: pen)
        ellipse(64, 47, 30, 29, skin, in: pen)

        let crown: CGFloat = 20
        switch appearance.headwear {
        case .beanie:
            ellipse(63, crown + 2, 27, 15, cloth, in: pen)
            roundRect(36, crown + 1, 55, 9, 3, cloth.shade(1.08), in: pen)
            for x in stride(from: 41, to: 89, by: 6) {
                line([(CGFloat(x), crown + 3), (CGFloat(x), crown + 8)], cloth.shade(0.77), width: 1, in: pen)
            }
            ellipse(63, crown - 12, 5, 5, cloth, in: pen)
        case .cap:
            ellipse(62, crown + 2, 26, 13, cloth, in: pen)
            path([(36, crown + 3), (87, crown + 3), (102, crown + 10), (99, crown + 14), (76, crown + 9), (36, crown + 9)], cloth.shade(0.86), in: pen)
            roundRect(58, crown - 5, 8, 8, 2, light, in: pen)
        case .sprout:
            line([(64, crown + 4), (65, crown - 6), (69, crown - 12)], cloth, width: 3, in: pen)
            ellipse(57, crown - 8, 9, 4, cloth, rotation: 0.5, in: pen)
            ellipse(75, crown - 13, 9, 4, cloth.shade(1.18), rotation: -0.55, in: pen)
        case .antenna:
            line([(64, crown + 3), (64, crown - 8)], light.shade(0.8), in: pen)
            ellipse(64, crown - 12, 4, 4, cloth, in: pen)
        case .mushroom:
            roundRect(57, 17, 14, 14, 4, light, in: pen)
            ellipse(64, 24, 31, 5, cloth.shade(0.65), in: pen)
            pen.beginPath()
            pen.move(to: CGPoint(x: 33, y: 23))
            pen.addCurve(to: CGPoint(x: 95, y: 23), control1: CGPoint(x: 36, y: 1), control2: CGPoint(x: 90, y: 1))
            pen.addQuadCurve(to: CGPoint(x: 33, y: 23), control: CGPoint(x: 64, y: 29))
            pen.setFillColor(cloth.cgColor)
            pen.fillPath()
            ellipse(48, 17, 4.5, 3, light, depth: false, rotation: -0.4, in: pen)
            ellipse(65, 12, 5, 3.5, light, depth: false, in: pen)
            ellipse(81, 18, 4, 3, light, depth: false, rotation: 0.4, in: pen)
        case .bandana:
            path([(37, 29), (42, 20), (62, 10), (85, 20), (90, 29)], cloth, in: pen)
            path([(62, 10), (70, 28), (90, 29), (85, 20)], cloth.shade(0.78), in: pen)
            path([(87, 25), (100, 31), (96, 37), (86, 29)], cloth, in: pen)
            path([(88, 27), (92, 42), (84, 37), (83, 27)], cloth.shade(0.78), in: pen)
            path([(38, 25), (88, 25), (88, 31), (38, 31)], cloth.shade(1.12), in: pen)
            ellipse(88, 28, 4, 4, cloth, in: pen)
        case .orbit:
            pen.saveGState()
            pen.translateBy(x: 64, y: 17)
            pen.rotate(by: -0.2)
            pen.beginPath()
            pen.addEllipse(in: CGRect(x: -29, y: -9, width: 58, height: 18))
            pen.setStrokeColor(cloth.cgColor)
            pen.setLineWidth(3)
            pen.setLineCap(.round)
            pen.setLineJoin(.round)
            pen.strokePath()
            pen.restoreGState()
            ellipse(87, 10, 5.5, 5.5, light, in: pen)
        case .pebbles:
            ellipse(64, 24, 20, 7, cloth, in: pen)
            ellipse(62, 15, 13, 6, light, in: pen)
            ellipse(65, 7, 7, 4, cloth.shade(1.1), in: pen)
        case .none:
            break
        }
    }

    private static func drawEyes(_ face: AvatarAppearance.Face, eyes: Eyes, in pen: CGContext) {
        let faceY: CGFloat = 48
        let glance: CGFloat = eyes == .glance ? 1.5 : 0
        for x: CGFloat in [53, 74] {
            switch face {
            case .glasses:
                let rect = CGRect(x: x - 7.25, y: 40.75, width: 14.5, height: 14.5)
                pen.setStrokeColor(ink.cgColor)
                pen.setLineWidth(2.2)
                pen.setLineCap(.round)
                pen.setLineJoin(.round)
                pen.addPath(CGPath(roundedRect: rect, cornerWidth: 4.5, cornerHeight: 4.5, transform: nil))
                pen.strokePath()
                pen.saveGState()
                pen.addPath(CGPath(
                    roundedRect: CGRect(x: x - 6.15, y: 41.85, width: 12.3, height: 12.3),
                    cornerWidth: 3.4, cornerHeight: 3.4, transform: nil
                ))
                pen.clip()
                if eyes == .blink {
                    line([(x - 2.5, faceY + 1), (x + 2.5, faceY + 1)], ink, in: pen)
                } else {
                    ellipse(x + glance, faceY, 1.7, 2.8, ink, depth: false, in: pen)
                }
                pen.restoreGState()
            case .wide:
                if eyes == .blink {
                    line([(x - 3, faceY + 1), (x + 3, faceY + 1)], ink, in: pen)
                } else {
                    ellipse(x, faceY, 5, 6, Color(255, 255, 255), depth: false, in: pen)
                    ellipse(x + glance, faceY, 2.5, 3.5, ink, depth: false, in: pen)
                }
            case .mellow:
                if eyes == .blink {
                    line([(x - 3.5, 49), (x + 3.5, 49)], ink, width: 2.2, in: pen)
                } else {
                    pen.saveGState()
                    pen.clip(to: CGRect(x: x - 5, y: 47.5, width: 10, height: 7))
                    ellipse(x, faceY, 4.5, 5, Color(255, 255, 255), depth: false, in: pen)
                    ellipse(x + glance, 49, 2, 3, ink, depth: false, in: pen)
                    pen.restoreGState()
                    line([(x - 4, 47.5), (x + 4, 47.5)], ink, width: 2.2, in: pen)
                }
            case .happy:
                arch(x, 49, bend: eyes == .blink ? -3 : -6, width: 2.7, in: pen)
            case .dashes:
                if eyes == .blink {
                    arch(x, 49, bend: 1.5, width: 2.8, in: pen)
                } else {
                    line([(x - 3, faceY), (x + 3, faceY)], ink, width: 2.8, in: pen)
                }
            case .dots:
                if eyes == .blink {
                    line([(x - 2.5, faceY + 1), (x + 2.5, faceY + 1)], ink, in: pen)
                } else {
                    ellipse(x + glance, faceY, 2.6, 4, ink, depth: false, in: pen)
                }
            }
        }
        if face == .glasses {
            line([(60.25, faceY - 1), (66.75, faceY - 1)], ink, width: 2.2, in: pen)
        }
    }

    private static func drawMouth(_ mouth: Mouth, in pen: CGContext) {
        let faceY: CGFloat = 48
        switch mouth {
        case .resting:
            line([(61, faceY + 13), (64, faceY + 15), (67, faceY + 13)], ink, in: pen)
        case .small:
            ellipse(64, faceY + 14, 2.4, 1.8, ink, depth: false, in: pen)
        case .open:
            ellipse(64, faceY + 14, 2.8, 2.8, ink, depth: false, in: pen)
        }
    }

    private static func ellipse(
        _ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ color: Color,
        depth: Bool = true, rotation: CGFloat = 0, in pen: CGContext
    ) {
        pen.saveGState()
        pen.translateBy(x: x, y: y)
        pen.rotate(by: rotation)
        pen.addEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
        if depth, let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [color.shade(1.15).cgColor, color.cgColor, color.shade(0.55).cgColor] as CFArray,
            locations: [0, 0.48, 1]
        ) {
            pen.clip()
            pen.drawRadialGradient(
                gradient, startCenter: CGPoint(x: -rx * 0.35, y: -ry * 0.42), startRadius: 1,
                endCenter: .zero, endRadius: max(rx, ry) * 1.08,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        } else {
            pen.setFillColor(color.cgColor)
            pen.fillPath()
        }
        pen.restoreGState()
    }

    private static func path(_ points: [(CGFloat, CGFloat)], _ color: Color, in pen: CGContext) {
        pen.beginPath()
        for (index, point) in points.enumerated() {
            let position = CGPoint(x: point.0, y: point.1)
            if index == 0 { pen.move(to: position) } else { pen.addLine(to: position) }
        }
        pen.closePath()
        pen.setFillColor(color.cgColor)
        pen.fillPath()
    }

    private static func line(
        _ points: [(CGFloat, CGFloat)], _ color: Color, width: CGFloat = 2, in pen: CGContext
    ) {
        pen.beginPath()
        pen.setStrokeColor(color.cgColor)
        pen.setLineWidth(width)
        pen.setLineCap(.round)
        pen.setLineJoin(.round)
        for (index, point) in points.enumerated() {
            let position = CGPoint(x: point.0, y: point.1)
            if index == 0 { pen.move(to: position) } else { pen.addLine(to: position) }
        }
        pen.strokePath()
    }

    private static func arch(
        _ x: CGFloat, _ y: CGFloat, bend: CGFloat, width: CGFloat, in pen: CGContext
    ) {
        pen.beginPath()
        pen.setStrokeColor(ink.cgColor)
        pen.setLineWidth(width)
        pen.setLineCap(.round)
        pen.setLineJoin(.round)
        pen.move(to: CGPoint(x: x - 3.5, y: y))
        pen.addQuadCurve(to: CGPoint(x: x + 3.5, y: y), control: CGPoint(x: x, y: y + bend))
        pen.strokePath()
    }

    private static func roundRect(
        _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat,
        _ color: Color, in pen: CGContext
    ) {
        pen.setFillColor(color.cgColor)
        pen.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerWidth: radius, cornerHeight: radius, transform: nil))
        pen.fillPath()
    }
}
