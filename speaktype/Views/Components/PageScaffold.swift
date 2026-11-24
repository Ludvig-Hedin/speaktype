import SwiftUI

/// Shared page frame: one centered reading column with a quiet title.
/// Every main screen uses it so headers, widths and spacing line up when switching tabs.
struct PageScaffold<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    /// Optional hover note shown as a small info icon after the subtitle.
    var subtitleHelp: String? = nil
    var spacing: CGFloat = 28
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            // Header-to-content gap is fixed so the first card never shifts between tabs;
            // `spacing` only sets the gap between content blocks.
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: title, subtitle: subtitle, subtitleHelp: subtitleHelp, trailing: trailing)
                VStack(alignment: .leading, spacing: spacing) {
                    content()
                }
            }
            .frame(maxWidth: Constants.UI.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Constants.UI.pageHorizontalPadding)
            .padding(.top, Constants.UI.pageTopPadding)
            .padding(.bottom, Constants.UI.pageTopPadding)
        }
    }
}

extension PageScaffold where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        subtitleHelp: String? = nil,
        spacing: CGFloat = 28,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleHelp = subtitleHelp
        self.spacing = spacing
        self.trailing = { EmptyView() }
        self.content = content
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var subtitleHelp: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typography.displayMedium)
                    .appleTitleTracking()
                    .foregroundStyle(Color.textPrimary)
                if let subtitle {
                    HStack(spacing: 6) {
                        Text(LocalizedStringKey(subtitle))
                            .font(Typography.bodySmall)
                            .foregroundStyle(Color.textMuted)
                        if let subtitleHelp {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textMuted)
                                .help(subtitleHelp)
                                .accessibilityLabel(subtitleHelp)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}

/// Small section label used above lists and groups inside a page.
struct SectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Typography.headlineSmall)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}

/// Hairline between rows inside a grouped list.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.border.opacity(0.6))
            .frame(height: 0.5)
    }
}
