import AppKit
import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            // Space for traffic lights
            Spacer()
                .frame(height: SidebarConstants.topInset)

            // Logo Header
            SidebarHeader()
                .padding(.horizontal, SidebarConstants.horizontalPadding)
                .padding(.bottom, SidebarConstants.headerBottomPadding)

            // Navigation Items
            VStack(spacing: SidebarConstants.itemSpacing) {
                ForEach(SidebarItem.allCases) { item in
                    SidebarButton(
                        item: item,
                        isSelected: selection == item,
                        action: { selection = item }
                    )
                }
            }
            .padding(.horizontal, SidebarConstants.itemHorizontalPadding)

            Spacer()

            // Build version indicator — debug only, never shown in production
            #if DEBUG
                Text(buildVersionString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.textMuted.opacity(0.35))
                    .padding(.bottom, 14)
            #else
                Spacer().frame(height: 14)
            #endif
        }
        .frame(width: SidebarConstants.width)
    }

    private var buildVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(version) (\(buildTimestamp))"
    }
}

// MARK: - Constants

private enum SidebarConstants {
    static let width: CGFloat = 220
    static let topInset: CGFloat = 48
    static let horizontalPadding: CGFloat = 22
    static let itemHorizontalPadding: CGFloat = 12
    static let headerBottomPadding: CGFloat = 20
    static let itemSpacing: CGFloat = 2
    static let bottomPadding: CGFloat = 20
    static let iconSize: CGFloat = 14
    static let itemVerticalPadding: CGFloat = 7
    static let itemCornerRadius: CGFloat = Constants.UI.sidebarItemCornerRadius
}

// MARK: - Components

private struct SidebarHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text("Hum")
                .font(Typography.sidebarLogo)
                .foregroundStyle(Color.textPrimary)

            Spacer()
        }
    }
}

struct SidebarButton: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.isFocusEffectEnabled) private var showsFocus
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: SidebarConstants.iconSize))
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textMuted)
                    .frame(width: 18)

                Text(item.rawValue)
                    .font(isSelected ? Typography.sidebarItemActive : Typography.sidebarItem)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, SidebarConstants.itemVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: SidebarConstants.itemCornerRadius, style: .continuous)
                    .fill(isSelected ? Color.bgSelected : (isHovered ? Color.bgHover : Color.clear))
            )
            .overlay {
                if showsFocus && isFocused {
                    RoundedRectangle(cornerRadius: SidebarConstants.itemCornerRadius, style: .continuous)
                        .strokeBorder(Color.accentBlue, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .focusEffectDisabled()
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            // If the sidebar row is torn down while hovered (e.g. window closes), balance the cursor stack.
            if isHovered {
                NSCursor.pop()
                isHovered = false
            }
        }
    }
}

private struct SidebarPromoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Try Hum Pro")
                    .font(Typography.sidebarPromoTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("✨")
                    .font(.system(size: 12))
            }

            Text("Upgrade for unlimited words")
                .font(Typography.sidebarPromoSubtitle)
                .foregroundStyle(Color.textMuted)

            Button(action: {}) {
                Text("Upgrade to Pro")
                    .font(Typography.sidebarPromoButton)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.border.opacity(0.45), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.stPlain)
            .padding(.top, 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sidebar Items

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case transcribeAudio = "Transcribe Audio"
    case history = "History"
    case statistics = "Statistics"
    case aiModels = "AI Models"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .transcribeAudio: return "waveform"
        case .history: return "doc.text"
        case .statistics: return "chart.bar"
        case .aiModels: return "cpu"
        case .settings: return "gearshape"
        }
    }
}
