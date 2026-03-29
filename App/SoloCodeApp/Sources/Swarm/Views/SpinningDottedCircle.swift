import SwiftUI

/// An animated dotted circle that rotates continuously while a sub-agent is running.
struct SpinningDottedCircle: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.03, to: 0.97)
            .stroke(
                DesignSystem.Colors.swarmColor.opacity(0.82),
                style: StrokeStyle(
                    lineWidth: 1.8,
                    lineCap: .round,
                    dash: [4.5, 6.5]
                )
            )
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(
                    .linear(duration: 1.15)
                    .repeatForever(autoreverses: false)
                ) {
                    rotation = 360
                }
            }
    }
}
