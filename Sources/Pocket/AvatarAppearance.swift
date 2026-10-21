import Foundation

struct AvatarAppearance: Codable, Equatable, Sendable {
    var palette: Palette = .campfire
    var headwear: Headwear = .none
    var face: Face = .dots
    var size: Size = .small

    enum Palette: String, CaseIterable, Codable, Sendable {
        case campfire, lichen, lilac, glacier, terminal
        var title: String { rawValue.capitalized }

        var colors: (skin: UInt32, cloth: UInt32, light: UInt32) {
            switch self {
            case .campfire: (0xd5a17c, 0x859276, 0xf3d4a7)
            case .lichen: (0xb2bf8a, 0xa19364, 0xe2e5b9)
            case .lilac: (0xb9a5ca, 0x7f8b9f, 0xe3d7ea)
            case .glacier: (0xa3cbcc, 0x658d92, 0xdef1df)
            case .terminal: (0xb8c6a0, 0x869575, 0xdce5bf)
            }
        }
    }

    enum Headwear: String, CaseIterable, Codable, Sendable {
        case none, beanie, cap, sprout, antenna, mushroom, bandana, orbit, pebbles
        var title: String {
            switch self {
            case .beanie: "Beanie"
            case .none: "None"
            case .cap: "Cap"
            case .sprout: "Sprout"
            case .antenna: "Antenna"
            case .mushroom: "Mushroom"
            case .bandana: "Bandana"
            case .orbit: "Orbit"
            case .pebbles: "Pebbles"
            }
        }
    }

    enum Face: String, CaseIterable, Codable, Sendable {
        case dots, wide, glasses, mellow, happy, dashes
        var title: String {
            switch self {
            case .dots: "Dot"
            case .wide: "Wide"
            case .glasses: "Glasses"
            case .mellow: "Mellow"
            case .happy: "Happy"
            case .dashes: "Dash"
            }
        }
    }

    enum Size: Int, CaseIterable, Codable, Sendable {
        case small = 40, medium = 48, large = 56
        var title: String {
            switch self {
            case .small: "S"
            case .medium: "M"
            case .large: "L"
            }
        }
        var points: CGFloat { CGFloat(rawValue) }
    }

    init() {}

    // Recover each choice independently when an older or newer app saved it.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        palette = (try? values.decode(Palette.self, forKey: .palette)) ?? .campfire
        headwear = (try? values.decode(Headwear.self, forKey: .headwear)) ?? .none
        let savedFace = try? values.decode(String.self, forKey: .face)
        face = savedFace == "sleepy" ? .mellow : savedFace.flatMap(Face.init(rawValue:)) ?? .dots
        size = (try? values.decode(Size.self, forKey: .size)) ?? .small
    }
}
