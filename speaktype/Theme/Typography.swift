//
//  Typography.swift
//  speaktype
//
//  Apple-native type: SF Pro (the system font) at every size. Weight discipline —
//  regular / medium / semibold only, never bold (per Apple HIG). Serif is retired;
//  display headings use SF Pro semibold with tight tracking applied at the call site
//  via `.appleTitleTracking()`. Numbers use `.monospacedDigit()` so counts don't jitter.
//

import SwiftUI

// MARK: - Typography System (SF Pro / system)

enum Typography {

    // MARK: - Display headings (SF Pro semibold — was serif)

    static let displayLarge = Font.system(size: 30, weight: .semibold)
    static let displayMedium = Font.system(size: 24, weight: .semibold)
    static let displaySmall = Font.system(size: 20, weight: .semibold)

    // MARK: - Headlines

    static let headlineLarge = Font.system(size: 18, weight: .semibold)
    static let headlineMedium = Font.system(size: 16, weight: .semibold)
    static let headlineSmall = Font.system(size: 14, weight: .semibold)

    // MARK: - Titles

    static let titleLarge = Font.system(size: 15, weight: .medium)
    static let titleMedium = Font.system(size: 14, weight: .medium)
    static let titleSmall = Font.system(size: 13, weight: .medium)

    // MARK: - Body

    static let bodyLarge = Font.system(size: 15, weight: .regular)
    static let bodyMedium = Font.system(size: 14, weight: .regular)
    static let bodySmall = Font.system(size: 13, weight: .regular)

    // MARK: - Labels

    static let labelLarge = Font.system(size: 14, weight: .medium)
    static let labelMedium = Font.system(size: 13, weight: .medium)
    static let labelSmall = Font.system(size: 12, weight: .medium)

    // MARK: - Captions

    static let caption = Font.system(size: 12, weight: .regular)
    static let captionSmall = Font.system(size: 11, weight: .regular)
    static let captionBold = Font.system(size: 11, weight: .semibold)

    // MARK: - Special

    static let mono = Font.system(size: 13, design: .monospaced)
    static let monoSmall = Font.system(size: 11, design: .monospaced)

    // MARK: - Stat / hero numbers (tabular figures)

    static let statValueXL = Font.system(size: 48, weight: .semibold).monospacedDigit()
    static let statValueL = Font.system(size: 28, weight: .semibold).monospacedDigit()
    static let statValueM = Font.system(size: 20, weight: .semibold).monospacedDigit()
    /// Legacy alias.
    static let statValue = statValueL
    static let statLabel = Font.system(size: 13, weight: .regular)

    static let badge = Font.system(size: 11, weight: .medium)

    // MARK: - Card typography

    static let cardTitle = Font.system(size: 17, weight: .semibold)
    static let cardSubtitle = Font.system(size: 14, weight: .regular)
    static let cardMeta = Font.system(size: 12, weight: .regular)
    static let cardMetaBold = Font.system(size: 12, weight: .medium)
    static let cardDescription = Font.system(size: 13, weight: .regular)
    static let buttonLabel = Font.system(size: 13, weight: .semibold)
    static let buttonLabelSmall = Font.system(size: 12, weight: .medium)

    // MARK: - Sidebar

    static let sidebarLogo = Font.system(size: 20, weight: .semibold)
    static let sidebarItem = Font.system(size: 15, weight: .regular)
    static let sidebarItemActive = Font.system(size: 15, weight: .semibold)
    static let sidebarBadge = Font.system(size: 10, weight: .medium)
    static let sidebarPromoTitle = Font.system(size: 14, weight: .semibold)
    static let sidebarPromoSubtitle = Font.system(size: 13, weight: .regular)
    static let sidebarPromoButton = Font.system(size: 13, weight: .medium)
}

// MARK: - Display tracking

extension View {
    /// Apple tightens tracking on large display text (~-0.015 at 24–30pt). Apply to
    /// screen titles / hero numbers so headings read "sculpted", not spread out.
    func appleTitleTracking() -> some View {
        self.tracking(-0.4)
    }
}
