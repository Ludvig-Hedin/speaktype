import SwiftUI

/// Soft base layer: neutral wash + subtle vertical depth (liquid-glass stacks read better on a non-flat ground).
struct AmbientBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.bgApp, Color.bgSidebar.opacity(0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
