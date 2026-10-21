import AppKit

/// In-process accessibility inspection; no assistive-access permission required.
@MainActor
public struct NativeAccessibility {
    private let object: NSObject

    public init(_ object: NSObject) {
        self.object = object
    }

    public static func enable() {
        // SwiftUI lazily creates virtual AX elements only for accessibility clients.
        NSApplication.shared.accessibilitySetValue(
            true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        )
    }

    public var identifier: String? { value("accessibilityIdentifier") as? String }

    public var frame: CGRect {
        (object as? any NSAccessibilityElementProtocol)?.accessibilityFrame() ?? .zero
    }

    public var text: String {
        let ownText = [value("accessibilityLabel") as? String, value("accessibilityValue") as? String]
            .compactMap { $0 }
        return (ownText + children.map(\.text)).joined(separator: " ")
    }

    public func descendant(identifier: String) -> Self? {
        if self.identifier == identifier { return self }
        return children.lazy.compactMap { $0.descendant(identifier: identifier) }.first
    }

    private var children: [Self] {
        (value("accessibilityChildren") as? [NSObject] ?? []).map(Self.init)
    }

    private func value(_ getter: String) -> Any? {
        // Virtual SwiftUI elements expose these public NSAccessibility getters but
        // conform only to NSAccessibilityElementProtocol, not the full protocol.
        let selector = NSSelectorFromString(getter)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
}
