import SwiftUI

/// Clessidra animata per il banner “indicizzazione in coda / in corso” nella sidebar.
struct SidebarIndexingHourglass: View {
    @State private var animate = false

    var body: some View {
        Image(systemName: "hourglass")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.orange)
            .rotationEffect(.degrees(animate ? 10 : -10))
            .scaleEffect(animate ? 1.06 : 0.94)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }
            .accessibilityHidden(true)
    }
}
