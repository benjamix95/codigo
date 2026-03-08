import SwiftUI

struct ActivityShimmerTrail: View {
    @State private var phase: CGFloat = 0

    private let trailWidth: CGFloat = 120
    private let silverColor = Color.white.opacity(0.35)

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    Color.clear,
                    silverColor.opacity(0.4),
                    silverColor,
                    silverColor.opacity(0.4),
                    Color.clear,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: trailWidth)
            .offset(x: phase * (geo.size.width + trailWidth * 2) - trailWidth)
            .blendMode(.plusLighter)
        }
        .onAppear {
            withAnimation(
                .linear(duration: 2.2)
                .repeatForever(autoreverses: false)
            ) { phase = 1 }
        }
    }
}

struct TextShimmerEffect: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = 0

    private let trailWidth: CGFloat = 80

    func body(content: Content) -> some View {
        if isActive {
            content
                .overlay {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.85),
                                Color.white.opacity(0.6),
                                Color.clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: trailWidth)
                        .offset(x: phase * (geo.size.width + trailWidth * 2) - trailWidth)
                        .blendMode(.plusLighter)
                    }
                    .mask { content }
                    .allowsHitTesting(false)
                }
                .onAppear {
                    phase = 0
                    withAnimation(
                        .linear(duration: 1.0)
                        .repeatForever(autoreverses: false)
                    ) { phase = 1 }
                }
        } else {
            content
        }
    }
}

extension View {
    func textShimmer(active: Bool) -> some View {
        modifier(TextShimmerEffect(isActive: active))
    }
}
