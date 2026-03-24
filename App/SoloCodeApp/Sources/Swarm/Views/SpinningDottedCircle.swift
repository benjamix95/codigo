import SwiftUI

/// An animated dotted circle that rotates continuously while a sub-agent is running.
struct SpinningDottedCircle: View {
    @State private var rotation: Double = 0

    var body: some View {
        Image(systemName: "circle.dotted")
            .font(.system(size: 14))
            .foregroundStyle(DesignSystem.Colors.swarmColor.opacity(0.7))
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(
                    .linear(duration: 2.0)
                    .repeatForever(autoreverses: false)
                ) {
                    rotation = 360
                }
            }
    }
}
