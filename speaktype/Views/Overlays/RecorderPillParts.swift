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
