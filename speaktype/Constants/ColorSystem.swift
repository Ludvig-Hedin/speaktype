import AppKit
import SwiftUI

// MARK: - SpeakType Design System
//
// Visual direction (2026 refresh): monochrome + liquid glass.
// — Lavender/purple tints removed; selection uses neutral grays so the UI reads “tool”, not “AI demo”.
// — Cards stack `.ultraThinMaterial` with a light surface tint + soft stroke for depth (Apple glass).
// — Spacing follows 4/8pt; corners are continuous and larger for a calmer, product-native feel.

extension Color {

    // MARK: - Core Palette

    /// Warm cream background (like Flow)
    static let cream = Color(hex: "FAF9F7")
    static let creamWarm = Color(hex: "F8F6F3")

    /// Dark theme
    static let ink = Color(hex: "1A1A1A")
    static let inkLight = Color(hex: "252525")
    static let inkSurface = Color(hex: "2F2F2F")

    /// Legacy names kept for call sites; values are neutral (no purple).
    static let lavender = Color(hex: "ECECEE")
    static let lavenderDark = Color(hex: "3A3A3C")

    // MARK: - Semantic Colors

    static let bgApp = Color(
        nsColor: NSColor(
            name: "bgApp",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "1A1A1A")
                    : NSColor(hex: "FAF9F7")
            }))

    static let bgContent = Color(
        nsColor: NSColor(
            name: "bgContent",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "1A1A1A")
                    : NSColor(hex: "FFFFFF")  // White content area like Flow
            }))

    static let bgSidebar = Color(
        nsColor: NSColor(
            name: "bgSidebar",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "1A1A1A")
                    : NSColor(hex: "F5F4F2")  // Slightly warmer than content
            }))

    static let bgSurface = Color(
        nsColor: NSColor(
            name: "bgSurface",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "252525")
                    : NSColor(hex: "FFFFFF")
            }))

    static let bgCard = Color(
        nsColor: NSColor(
            name: "bgCard",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "252525")
                    : NSColor(hex: "FFFFFF")
            }))

    static let bgHover = Color(
        nsColor: NSColor(
            name: "bgHover",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "2F2F2F")
                    : NSColor(hex: "F5F4F2")
            }))

    static let bgSelected = Color(
        nsColor: NSColor(
            name: "bgSelected",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "3A3A3C")  // Elevated neutral (sidebar / lists)
                    : NSColor(hex: "E8E8ED")  // Soft gray selection, not tinted
            }))

    // MARK: - Borders

    static let border = Color(
        nsColor: NSColor(
            name: "border",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "3A3A3A")
                    : NSColor(hex: "E8E6E3")
            }))

    static let borderSubtle = Color(
        nsColor: NSColor(
            name: "borderSubtle",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "2F2F2F")
                    : NSColor(hex: "EFEDEA")
            }))

    static let borderCard = Color(
        nsColor: NSColor(
            name: "borderCard",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "3A3A3A")
                    : NSColor(hex: "E8E6E3")
            }))

    /// Focus / emphasis ring — neutral graphite, not purple.
    static let borderActive = Color(hex: "48484A")

    // MARK: - Text

    static let textPrimary = Color(
        nsColor: NSColor(
            name: "textPrimary",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "FFFFFF")
                    : NSColor(hex: "1A1A1A")
            }))

    static let textSecondary = Color(
        nsColor: NSColor(
            name: "textSecondary",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "A0A0A0")
                    : NSColor(hex: "6B6B6B")
            }))

    static let textMuted = Color(
        nsColor: NSColor(
            name: "textMuted",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "707070")
                    : NSColor(hex: "9A9A9A")
            }))

    static let textDisabled = Color(
        nsColor: NSColor(
            name: "textDisabled",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "505050")
                    : NSColor(hex: "C0C0C0")
            }))

    // MARK: - Sidebar

    static let sidebarItem = Color(
        nsColor: NSColor(
            name: "sidebarItem",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "A0A0A0")
                    : NSColor(hex: "6B6B6B")
            }))

    static let sidebarItemHoverBg = Color(
        nsColor: NSColor(
            name: "sidebarItemHoverBg",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "2F2F2F")
                    : NSColor(hex: "F0EFED")
            }))

    // MARK: - Accents

    static let accentPrimary = Color(
        nsColor: NSColor(
            name: "accentPrimary",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "FFFFFF")  // White in Dark Mode for high contrast
                    : NSColor(hex: "1A1A1A")  // Black in Light Mode
            }))
    static let accentSuccess = Color(hex: "22C55E")
    static let accentWarning = Color(hex: "F59E0B")
    static let accentError = Color(hex: "EF4444")
    static let accentBlue = Color(hex: "3B82F6")

    // Chart colors
    static let chartRed = Color(hex: "A62D35")
    static let chartBlue = Color(hex: "2D5DA6")
    static let chartGreen = Color(hex: "22C55E")

    // Legacy (formerly navy — now neutral for charts/dividers)
    static let navyInk = Color(hex: "3A3A3C")
    static let navyLight = Color(hex: "545456")
    static let navyMuted = Color(hex: "6B6B6B")
    static let charcoal = Color(hex: "1A1A1A")
    static let charcoalLight = Color(hex: "252525")
    static let charcoalSurface = Color(hex: "2F2F2F")
    static let accentWarm = Color(hex: "F59E0B")
    static let accentCool = Color(hex: "3B82F6")
    static let accentRed = Color(hex: "EF4444")
    static let accentRedSoft = Color(hex: "EF4444").opacity(0.1)
    static let accentBlueSoft = Color(hex: "3B82F6").opacity(0.1)

    // MARK: - Buttons

    static let btnPrimaryBg = Color(hex: "1A1A1A")
    static let btnPrimaryFg = Color(hex: "FFFFFF")

    static let btnSecondaryBg = Color(
        nsColor: NSColor(
            name: "btnSecondaryBg",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "2F2F2F")
                    : NSColor(hex: "F0EFED")
            }))

    static let btnSecondaryHover = Color(
        nsColor: NSColor(
            name: "btnSecondaryHover",
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: "3A3A3A")
                    : NSColor(hex: "E5E3E0")
            }))

    // MARK: - Badges

    static let badgeVoiceBg = Color(hex: "22C55E").opacity(0.12)
    static let badgeVoiceText = Color(hex: "22C55E")
    static let badgeMusicBg = Color(hex: "3B82F6").opacity(0.12)
    static let badgeMusicText = Color(hex: "3B82F6")
    static let badgeMutedBg = Color(hex: "9A9A9A").opacity(0.12)
    static let badgeMutedText = Color(hex: "9A9A9A")

    // No gradients (single-stop kept for call-site compatibility)
    static let gradientPrimary = LinearGradient(
        colors: [Color(hex: "1A1A1A")], startPoint: .leading, endPoint: .trailing)
    static let gradientButton = LinearGradient(
        colors: [Color(hex: "1A1A1A")], startPoint: .leading, endPoint: .trailing)
    static let gradientSidebarActive = LinearGradient(
        colors: [Color(hex: "E8E8ED")], startPoint: .leading, endPoint: .trailing)
    static let gradientWarm = LinearGradient(
        colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
}

// MARK: - Shadow Modifiers

extension View {
    func cardShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
    }

    func softShadow() -> some View {
        self.shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 1)
    }

    func elevatedShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Reusable Card Modifier

struct ThemedCardModifier: ViewModifier {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = Constants.UI.cardCornerRadius
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .padding(padding)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.05)
                            : Color.white.opacity(0.72)
                    )
                }
            }
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    Color.border.opacity(colorScheme == .dark ? 0.45 : 0.55),
                    lineWidth: 1
                )
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.14 : 0.55),
                            Color.white.opacity(0.04),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.05), radius: 14, x: 0, y: 6)
    }
}

extension View {
    /// Glass-tinted card: material + neutral tint + hairline — reads “system chrome”, not flat dashboard.
    func themedCard(padding: CGFloat = 20, cornerRadius: CGFloat = Constants.UI.cardCornerRadius)
        -> some View
    {
        modifier(ThemedCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Reusable Button Styles

struct STButtonPrimary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.bodyMedium)
            // Inverted pair: light = ink pill on cream label color; dark = white pill on ink label.
            .foregroundStyle(Color.bgApp)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.accentPrimary)
            .clipShape(Capsule(style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .modifier(ClickActionPointerCursorModifier())
    }
}

struct STButtonSecondary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.bodyMedium)
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.border.opacity(0.55), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .modifier(ClickActionPointerCursorModifier())
    }
}

struct STButtonGhost: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.bodySmall)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                configuration.isPressed ? Color.bgHover : Color.clear,
                in: Capsule(style: .continuous)
            )
            .modifier(ClickActionPointerCursorModifier())
    }
}

/// Plain label with pointing-hand cursor (replaces `.plain` for clickable controls).
struct STPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(ClickActionPointerCursorModifier())
    }
}

extension ButtonStyle where Self == STPlainButtonStyle {
    static var stPlain: STPlainButtonStyle { STPlainButtonStyle() }
}

extension ButtonStyle where Self == STButtonPrimary {
    static var stPrimary: STButtonPrimary { STButtonPrimary() }
}

extension ButtonStyle where Self == STButtonSecondary {
    static var stSecondary: STButtonSecondary { STButtonSecondary() }
}

extension ButtonStyle where Self == STButtonGhost {
    static var stGhost: STButtonGhost { STButtonGhost() }
}

// MARK: - Selection State Helper

struct SelectionBackground: View {
    let isSelected: Bool
    let isHovered: Bool
    var cornerRadius: CGFloat = Constants.UI.sidebarItemCornerRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                isSelected
                    ? Color.bgSelected
                    : (isHovered ? Color.bgHover : Color.clear)
            )
    }
}
