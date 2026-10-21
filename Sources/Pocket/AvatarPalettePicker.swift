import AppKit
import SwiftUI

struct AvatarPalettePicker: NSViewRepresentable {
    @Binding var selection: AvatarAppearance.Palette

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        for (index, palette) in AvatarAppearance.Palette.allCases.enumerated() {
            let button = PaletteButton(title: palette.title, target: context.coordinator,
                                       action: #selector(Coordinator.selectPalette(_:)))
            button.tag = index
            button.setButtonType(.toggle)
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.image = swatch(palette, selected: false)
            button.alternateImage = swatch(palette, selected: true)
            button.focusRingType = .exterior
            button.toolTip = palette.title
            button.setAccessibilityLabel("\(palette.title) palette")
            stack.addArrangedSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 36),
                button.heightAnchor.constraint(equalToConstant: 36),
            ])
        }
        return stack
    }

    func updateNSView(_ stack: NSStackView, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.updateSelection(in: stack)
    }

    private func swatch(_ palette: AvatarAppearance.Palette, selected: Bool) -> NSImage {
        let colors = palette.colors
        return NSImage(size: NSSize(width: 36, height: 36), flipped: false) { _ in
            func color(_ hex: UInt32) -> NSColor {
                NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                        green: CGFloat((hex >> 8) & 0xff) / 255,
                        blue: CGFloat(hex & 0xff) / 255, alpha: 1)
            }
            NSGraphicsContext.saveGraphicsState()
            let circle = NSBezierPath(ovalIn: NSRect(x: 6, y: 6, width: 24, height: 24))
            circle.addClip()
            color(colors.cloth).setFill()
            circle.fill()
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: 6, y: 6))
            triangle.line(to: NSPoint(x: 6, y: 30))
            triangle.line(to: NSPoint(x: 30, y: 30))
            triangle.close()
            color(colors.skin).setFill()
            triangle.fill()
            NSGraphicsContext.restoreGraphicsState()
            if selected {
                NSColor.labelColor.setStroke()
                let ring = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 32, height: 32))
                ring.lineWidth = 2
                ring.stroke()
            }
            return true
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<AvatarAppearance.Palette>

        init(selection: Binding<AvatarAppearance.Palette>) { self.selection = selection }

        @objc func selectPalette(_ sender: NSButton) {
            selection.wrappedValue = AvatarAppearance.Palette.allCases[sender.tag]
            if let stack = sender.superview as? NSStackView { updateSelection(in: stack) }
        }

        func updateSelection(in stack: NSStackView) {
            for case let button as NSButton in stack.arrangedSubviews {
                let selected = AvatarAppearance.Palette.allCases[button.tag] == selection.wrappedValue
                let changed = (button.state == .on) != selected
                button.state = selected ? .on : .off
                button.setAccessibilityValue(selected ? "Selected" : "Not selected")
                button.setAccessibilitySelected(selected)
                if changed { NSAccessibility.post(element: button, notification: .valueChanged) }
            }
        }
    }
}

// Keep standard button drawing and keyboard handling, with a circular native focus ring.
private final class PaletteButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override func drawFocusRingMask() { NSBezierPath(ovalIn: focusRingMaskBounds).fill() }
}
