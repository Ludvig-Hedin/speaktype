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
            // Suppress the system keyboard focus ring so the first nav row isn't
            // outlined (accent-colored) the moment the window opens.
            .focusEffectDisabled()

            Spacer()

            // 2048 Labs branding link
            Button(action: {
                NSWorkspace.shared.open(URL(string: "https://2048labs.com")!)
            }) {
                Text("2048 LABS")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(Color.textMuted.opacity(0.25))
            }
            .buttonStyle(.stPlain)
            .padding(.bottom, 6)

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
    static let width: CGFloat = 260
    static let topInset: CGFloat = 52
    static let horizontalPadding: CGFloat = 20
    static let itemHorizontalPadding: CGFloat = 14
    static let headerBottomPadding: CGFloat = 28
    static let itemSpacing: CGFloat = 2
    static let bottomPadding: CGFloat = 20
    static let iconSize: CGFloat = 17
    static let itemVerticalPadding: CGFloat = 10
    static let itemCornerRadius: CGFloat = Constants.UI.sidebarItemCornerRadius
}

// MARK: - Components

private struct SidebarHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)

            Text("SpeakType")
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
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: SidebarConstants.iconSize))
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textMuted)
                    .frame(width: 20)

                Text(item.rawValue)
                    .font(isSelected ? Typography.sidebarItemActive : Typography.sidebarItem)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, SidebarConstants.itemVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: SidebarConstants.itemCornerRadius, style: .continuous)
                    .fill(isSelected ? Color.bgSelected : (isHovered ? Color.bgHover : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SidebarConstants.itemCornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.textPrimary.opacity(isSelected ? 0.12 : 0),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                Text("Try SpeakType Pro")
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
