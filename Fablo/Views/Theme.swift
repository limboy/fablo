import SwiftUI

enum Theme {
    // Monochrome, neutral greys: the accent is ink itself (black on light, white on dark).
    static let paper = Color(light: 0xFAFAFA, dark: 0x0A0A0A)
    static let card = Color(light: 0xF4F4F5, dark: 0x1C1C1E)
    static let raised = Color(light: 0xFFFFFF, dark: 0x141414)
    static let border = Color(light: 0xE4E4E7, dark: 0x27272A)
    static let ink = Color(light: 0x0A0A0A, dark: 0xFAFAFA)
    static let muted = Color(light: 0x71717A, dark: 0xA1A1AA)
    static let accent = Color(light: 0x171717, dark: 0xFAFAFA)
    /// Text and icons drawn on top of `accent`.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0A0A0A)

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
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
        #else
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #endif
    }
}

extension PlatformColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// A filled accent capsule that keeps its fill when the window is inactive
/// (the Mac greys out `.borderedProminent`, which would leave its onAccent label unreadable).
struct AccentCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(Theme.accent, in: Capsule())
            .contentShape(.capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
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
        #if os(macOS)
        .font(.system(size: 12, weight: .medium))
        #else
        .font(.footnote.weight(.medium))
        #endif
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color, in: Capsule())
    }
}
