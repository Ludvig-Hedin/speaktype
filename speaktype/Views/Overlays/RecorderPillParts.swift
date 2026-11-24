import SwiftUI

/// Live voice waveform for the recorder pill. Drawn in one `Canvas` per frame instead of
/// animating many views, and paused entirely when the mic is not live.
struct LiveWaveform: View {
    let level: Float
    let isLive: Bool

    private let barCount = 11
    private let barWidth: CGFloat = 2.5
    private let spacing: CGFloat = 2.5
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 18

    @State private var smoothed: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isLive)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let center = CGFloat(barCount - 1) / 2
                let total = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
                var x = (size.width - total) / 2
                for i in 0..<barCount {
                    // Middle bars reach higher; a slow wave keeps the shape alive.
                    let distance = abs(CGFloat(i) - center) / center
                    let weight = 1 - distance * 0.55
                    let wave = 0.65 + 0.35 * sin(t * 7 + Double(i) * 0.85)
                    let energy = isLive ? smoothed * weight * CGFloat(wave) : 0
                    let h = minHeight + (maxHeight - minHeight) * min(1, energy)
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                    gc.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                            with: .color(.white.opacity(0.92)))
                    x += barWidth + spacing
                }
            }
        }
        .frame(width: CGFloat(barCount) * (barWidth + spacing) - spacing, height: maxHeight)
        .onChange(of: level) { _, newValue in
            // Fast attack, slower release, so speech reads as motion instead of flicker.
            let target = CGFloat(pow(max(0, newValue), 0.75))
            let blend: CGFloat = target > smoothed ? 0.6 : 0.18
            smoothed += (target - smoothed) * blend
        }
        .onChange(of: isLive) { _, live in
            if !live { smoothed = 0 }
        }
        .accessibilityLabel("Listening")
    }
}

/// Three soft dots that breathe while text is being transcribed and cleaned up.
struct WorkingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    let phase = sin(t * 5.5 - Double(i) * 0.7)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 5, height: 5)
                        .opacity(0.35 + 0.6 * (phase + 1) / 2)
                        .scaleEffect(0.85 + 0.2 * (phase + 1) / 2)
                }
            }
        }
        .frame(height: 18)
        .accessibilityLabel("Writing")
    }
}

// MARK: - Pill controls

/// Round control in the recorder pill. Cancel is a quiet grey disc with a white X; finish is
/// a white disc with a dark checkmark, so the action that inserts text reads first.
struct PillCircleIcon: View {
    enum Kind { case cancel, finish }
    let kind: Kind
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(kind == .finish ? Color.white : Color.white.opacity(0.3))
            Image(systemName: kind == .finish ? "checkmark" : "xmark")
                .font(.system(size: kind == .finish ? 10 : 9, weight: .bold))
                .foregroundStyle(kind == .finish ? Color.black : Color.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Tooltips

/// A hovered pill element: its current tooltip text and its frame.
struct PillTooltipEntry {
    let text: String
    let anchor: Anchor<CGRect>
}

/// The recorder lives in a non-activating panel, where macOS never shows `.help` tooltips.
/// Pill elements register under a stable id (the text can change while hovered, e.g.
/// "Transcribing…" → "Polishing…"); the recorder draws the hovered one above the pill.
struct PillTooltipAnchors: PreferenceKey {
    static let pillKey = "\u{0}pill"
    static var defaultValue: [String: PillTooltipEntry] { [:] }
    static func reduce(value: inout [String: PillTooltipEntry], nextValue: () -> [String: PillTooltipEntry]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct PillTooltipTarget: ViewModifier {
    let id: String
    let text: String
    @Binding var shown: String?
    @State private var showTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: PillTooltipAnchors.self, value: .bounds) {
                [id: PillTooltipEntry(text: text, anchor: $0)]
            }
            .onHover { inside in
                showTask?.cancel()
                if inside {
                    // A short rest before showing, like a native tooltip but quicker.
                    showTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        shown = id
                    }
                } else if shown == id {
                    shown = nil
                }
            }
            .onDisappear {
                showTask?.cancel()
                if shown == id { shown = nil }
            }
    }
}

extension View {
    /// Show `text` in a dark bubble above the recorder pill while this element is hovered.
    func pillTooltip(_ text: String, id: String, shown: Binding<String?>) -> some View {
        modifier(PillTooltipTarget(id: id, text: text, shown: shown))
    }

    /// Adds the pill's own frame to the tooltip anchors without replacing its children's.
    func pillTooltipFrame() -> some View {
        transformAnchorPreference(key: PillTooltipAnchors.self, value: .bounds) { value, anchor in
            value[PillTooltipAnchors.pillKey] = PillTooltipEntry(text: "", anchor: anchor)
        }
    }
}

/// Dark bubble used for recorder tooltips.
struct PillTooltipBubble: View {
    let text: String

    var body: some View {
        label
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.black.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            )
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
            .allowsHitTesting(false)
    }

    /// Short tips sit on one line; longer ones wrap at a readable width.
    @ViewBuilder private var label: some View {
        let text = Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.white.opacity(0.95))
            .multilineTextAlignment(.center)
        if self.text.count <= 40 {
            text.lineLimit(1).fixedSize()
        } else {
            text.lineLimit(4).frame(width: 250).fixedSize(horizontal: false, vertical: true)
        }
    }
}
