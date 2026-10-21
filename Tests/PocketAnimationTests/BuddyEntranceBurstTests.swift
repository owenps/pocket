import AppKit
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct BuddyEntranceBurstTests {
    @Test(arguments: [false, true], AvatarAppearance.Size.allCases)
    func burstOnlyPaintsDuringItsBriefWindow(reduceMotion: Bool, size: AvatarAppearance.Size) throws {
        try withBurst(size: size, palette: .campfire, reduceMotion: reduceMotion) { host in
            let frame = host.frame
            var peakMass = 0.0
            for progress in [0.0, 0.13 / 0.34, 0.14 / 0.34, 0.20 / 0.34, 0.29 / 0.34, 1.0] {
                withTransaction(Transaction(animation: nil)) {
                    host.rootView = burst(size: size, palette: .campfire,
                                          progress: progress, reduceMotion: reduceMotion)
                }
                let visible = !reduceMotion && progress >= 0.14 / 0.34 && progress < 0.29 / 0.34
                let image = try rendered(host) { image in
                    let mass = inkMass(image)
                    if !visible { return mass < 0.01 }
                    return mass > 1 && (peakMass == 0 || mass < peakMass - 0.5)
                }
                let mass = inkMass(image)
                #expect(host.frame == frame)
                #expect(host.frame.size == CGSize(width: size.points + 24, height: size.points + 24))
                #expect(host.window?.isVisible == false)
                if visible {
                    #expect(mass > 1)
                    if peakMass == 0 {
                        peakMass = mass
                        #expect(rayCount(image) == 3)
                    } else {
                        #expect(mass < peakMass)
                    }
                } else {
                    #expect(mass < 0.01)
                }
            }
        }
    }

    @Test(arguments: AvatarAppearance.Palette.allCases, AvatarAppearance.Size.allCases)
    func peakUsesPaletteLight(palette: AvatarAppearance.Palette, size: AvatarAppearance.Size) throws {
        try withBurst(size: size, palette: palette, reduceMotion: false, progress: 0.14 / 0.34) { host in
            let frame = host.frame
            let image = try rendered(host) { inkMass($0) > 1 }
            let colors = paintedColors(image)
            try #require(!colors.isEmpty)
            let light = palette.colors.light
            let expected = [Double((light >> 16) & 0xff), Double((light >> 8) & 0xff), Double(light & 0xff)]
            let expectedMax = try #require(expected.max())
            // Normalize brightness: opacity and edge coverage must not change the hue.
            for color in colors {
                let actual = [Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)]
                let actualMax = try #require(actual.max())
                for (actual, expected) in zip(actual, expected) {
                    #expect(abs(actual / actualMax - expected / expectedMax) < 0.02)
                }
            }
            #expect(rayCount(image) == 3)
            #expect(host.frame == frame)
            #expect(host.window?.isVisible == false)
        }
    }

    private func burst(size: AvatarAppearance.Size, palette: AvatarAppearance.Palette,
                       progress: Double, reduceMotion: Bool) -> AnyView {
        AnyView(BuddyEntranceBurst(palette: palette, progress: progress)
            .frame(width: size.points, height: size.points)
            .padding(12)
            .background(Color.black)
            .environment(\._accessibilityReduceMotion, reduceMotion)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            })
    }

    private func withBurst(size: AvatarAppearance.Size, palette: AvatarAppearance.Palette,
                           reduceMotion: Bool, progress: Double = 0,
                           body: (NSHostingView<AnyView>) throws -> Void) rethrows {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: size.points + 24, height: size.points + 24)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        // Never order/show the window; all rendering stays offscreen.
        let host = NSHostingView(rootView: burst(size: size, palette: palette,
                                                progress: progress, reduceMotion: reduceMotion))
        host.sizingOptions = []
        window.contentView = host
        host.frame = frame
        defer { window.contentView = nil }
        try body(host)
    }

    private func rendered(_ view: NSView, until condition: (NSBitmapImageRep) -> Bool) throws -> NSBitmapImageRep {
        let deadline = Date(timeIntervalSinceNow: 2)
        repeat {
            view.layoutSubtreeIfNeeded()
            let image = try snapshot(view)
            if condition(image) { return image }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        } while Date() < deadline
        let image = try snapshot(view)
        try #require(condition(image), "Expected burst rendering before timeout")
        return image
    }

    private func snapshot(_ view: NSView) throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private func inkMass(_ image: NSBitmapImageRep) -> Double {
        var mass = 0.0
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y) else { continue }
                mass += Double((color.redComponent + color.greenComponent + color.blueComponent) * color.alphaComponent)
            }
        }
        return mass
    }

    private func paintedColors(_ image: NSBitmapImageRep) -> [NSColor] {
        var colors: [NSColor] = []
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      max(color.redComponent, color.greenComponent, color.blueComponent) > 0.2
                else { continue }
                colors.append(color)
            }
        }
        return colors
    }

    // Count separated painted regions, without depending on ray paths or angles.
    private func rayCount(_ image: NSBitmapImageRep) -> Int {
        let width = image.pixelsWide
        var remaining = Set<Int>()
        for y in 0..<image.pixelsHigh {
            for x in 0..<width {
                guard let color = image.colorAt(x: x, y: y),
                      max(color.redComponent, color.greenComponent, color.blueComponent) * color.alphaComponent > 0.1
                else { continue }
                remaining.insert(y * width + x)
            }
        }
        var count = 0
        while let first = remaining.first {
            remaining.remove(first)
            var pending = [first]
            var pixels = 0
            while let pixel = pending.popLast() {
                pixels += 1
                let x = pixel % width, y = pixel / width
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < image.pixelsHigh else { continue }
                        let neighbor = ny * width + nx
                        if remaining.remove(neighbor) != nil { pending.append(neighbor) }
                    }
                }
            }
            if pixels >= 3 { count += 1 }
        }
        return count
    }
}
