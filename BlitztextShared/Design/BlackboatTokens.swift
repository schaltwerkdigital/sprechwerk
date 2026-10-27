import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Design tokens for the native apps. Sprechwerk replaces the Blackboat values with the
// Schaltwerk Digital palette (schaltwerkdigital.de): turquoise 2CD5C4, dark turquoise 009384,
// green 46BB0F, dark grey 2A2D34, light grey F6F7F9. Light mode uses the dark turquoise for
// text and buttons, the turquoise has too little contrast on white. The names stay, so
// Blitztext updates merge without touching every view; do not add colours elsewhere.

enum BlackboatColor {
    // MARK: Surfaces and text

    static let surfaceBase = dynamic(light: 0xF6F7F9, dark: 0x1F2126)
    static let surfaceElevated = dynamic(light: 0xFFFFFF, dark: 0x2A2D34)
    static let surfaceHover = dynamic(light: 0xF1F2F4, dark: 0x353941)
    static let textPrimary = dynamic(light: 0x2A2D34, dark: 0xFFFFFF)
    static let textSecondary = dynamic(light: 0x5C5F66, dark: 0xD9DBDF)
    static let border = dynamic(light: 0xE4E4E4, dark: 0x4A4E57)

    // MARK: Actions

    /// Primary buttons and the recording action: dark turquoise by day, turquoise at night.
    static let buttonPrimary = dynamic(light: 0x009384, dark: 0x2CD5C4)
    static let buttonPrimaryPressed = dynamic(light: 0x00756A, dark: 0x23AA9C)
    static let buttonPrimaryText = dynamic(light: 0xFFFFFF, dark: 0x14161A)
    /// Accent for text, icons and selection.
    static let accent = dynamic(light: 0x009384, dark: 0x2CD5C4)
    static let focusRing = dynamic(light: 0x2CD5C4, dark: 0x2CD5C4)

    // MARK: Feedback

    static let success = dynamic(light: 0x46BB0F, dark: 0x46BB0F)
    /// Positive status as text or icon: a darker green by day for contrast.
    static let successForeground = dynamic(light: 0x358C0B, dark: 0x6FD33A)
    static let error = dynamic(light: 0xD94C76, dark: 0xD94C76)

    // MARK: Accent sources (day, evening, night)

    /// The three accent families of design.json. Modes use one each; on dark
    /// surfaces the tertiary tone replaces the primary for contrast.
    enum Source {
        case day, evening, night

        var primary: Color {
            switch self {
            case .day: return dynamic(light: 0x009384, dark: 0x2CD5C4)
            case .evening: return dynamic(light: 0x358C0B, dark: 0x6FD33A)
            case .night: return dynamic(light: 0x2A2D34, dark: 0xC9CDD4)
            }
        }

        /// Filled surfaces (buttons, the microphone): primary to secondary in every mode.
        var gradient: [Color] {
            switch self {
            case .day: return [hex(0x2CD5C4), hex(0x009384)]
            case .evening: return [hex(0x46BB0F), hex(0x358C0B)]
            case .night: return [hex(0x4A4E57), hex(0x2A2D34)]
            }
        }
    }

    // MARK: - Helpers

    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? platformColor(dark) : platformColor(light) })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? platformColor(dark) : platformColor(light)
        })
        #endif
    }

    #if canImport(UIKit)
    static func platformColor(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
    #elseif canImport(AppKit)
    static func platformColor(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
    #endif
}

/// Radii of design.json (--radius-*).
enum BlackboatRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
}

/// Type roles of design.json. Headlines use Public Sans; running text stays in the
/// system font so Dynamic Type and native controls keep working.
enum BlackboatType {
    enum Weight: String {
        case regular = "PublicSans-Regular"
        case semibold = "PublicSans-SemiBold"
        case bold = "PublicSans-Bold"
        case extraBold = "PublicSans-ExtraBold"
    }

    /// Public Sans at a size that scales with Dynamic Type.
    static func publicSans(_ size: CGFloat, _ weight: Weight, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    /// type-heading-xl: 36 / 700
    static let headingXL = publicSans(36, .bold, relativeTo: .largeTitle)
    /// type-heading-l: 30 / 700
    static let headingL = publicSans(30, .bold, relativeTo: .title)
    /// type-heading-m: 24 / 600
    static let headingM = publicSans(24, .semibold, relativeTo: .title2)
    /// Card and section titles: body size, strong weight
    static let title = publicSans(17, .semibold, relativeTo: .headline)
    /// type-subtitle: 13 / 600, uppercase eyebrow with 0.2em tracking
    static let eyebrow = publicSans(13, .semibold, relativeTo: .footnote)
}
