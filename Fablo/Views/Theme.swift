import SwiftUI
import UIKit

enum Theme {
    static let paper = Color(light: 0xF9F9F0, dark: 0x1C1C19)
    static let card = Color(light: 0xF0F0E3, dark: 0x2A2A25)
    static let raised = Color(light: 0xFFFFFC, dark: 0x262622)
    static let ink = Color(light: 0x1D1D1B, dark: 0xF2F2EA)
    static let muted = Color(light: 0x5F5F58, dark: 0xA9A99E)
    static let accent = Color(light: 0xD9774B, dark: 0xF09A6E)

    static func chunk(_ role: ChunkRole) -> Color? {
        switch role {
        case .topic, .subject, .object: Color(light: 0xE6F0FB, dark: 0x22344A)
        case .predicate: Color(light: 0xFCE2D0, dark: 0x4A3022)
        case .modifier: Color(light: 0xF6F6F2, dark: 0x34342F)
        case .complement: Color(light: 0xEEE7F8, dark: 0x352B48)
        case .adverbial: Color(light: 0xE4F3E6, dark: 0x24392A)
        case .connector, .other: nil
        }
    }

    static func pos(_ pos: PartOfSpeech) -> Color? {
        switch pos {
        case .noun, .pronoun, .number: Color(light: 0xFFF27A, dark: 0x8F8420)
        case .verb, .auxiliary: Color(light: 0xBFE09A, dark: 0x4F7A2A)
        case .particle, .preposition, .conjunction, .determiner: Color(light: 0xA6DBE2, dark: 0x2E6E78)
        case .adjective: Color(light: 0xF8C3D1, dark: 0x8A3D52)
        case .adverb: Color(light: 0xD6C8F2, dark: 0x5B4A8A)
        case .interjection, .other: Color(light: 0xE2E2D6, dark: 0x4A4A42)
        case .punctuation: nil
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// A small rounded tag used for level / genre / role labels.
struct TagLabel: View {
    let text: String
    var systemImage: String?
    var color: Color = Theme.card

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color, in: Capsule())
    }
}
