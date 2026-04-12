import SwiftUI

extension Color {
    /// Neutral graphite from the premium palette (`#48484A`).
    static let appGraphite = Color(hex: "48484A")

    /// Misleading legacy name: this color is graphite gray, not red. Use ``appGraphite`` for this neutral, or ``Color.accentError`` / `Color.red` for errors.
    @available(*, deprecated, renamed: "appGraphite", message: "Not red; use appGraphite for this gray or Color.accentError for errors.")
    static var appRed: Color { appGraphite }
    static let sidebarBackground = Color.bgSidebar
    static let contentBackground = Color.bgSurface
}
