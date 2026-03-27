import AppKit
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = 0

    private let trailWidth: CGFloat = 96

    private var shimmerStops: [Color] {
        // Su etichette tertiary/quaternary lo sweep troppo “flat” sparisce; sweep leggermente caldo/scuro legge meglio.
        let core: Color
        if colorScheme == .dark {
            core = Color(red: 0.96, green: 0.93, blue: 0.88)
        } else {
            core = Color(nsColor: .textColor).opacity(0.22)
        }
        let isDark = colorScheme == .dark
        return [
            Color.clear,
            core.opacity(isDark ? 0.35 : 0.5),
            core.opacity(isDark ? 0.95 : 0.78),
            core.opacity(isDark ? 0.35 : 0.5),
            Color.clear,
        ]
    }

    private func startPhaseAnimation() {
        phase = 0
        withAnimation(
            .linear(duration: 1.05)
            .repeatForever(autoreverses: false)
        ) {
            phase = 1
        }
    }

    func body(content: Content) -> some View {
        if isActive {
            content
                .compositingGroup()
                .overlay {
                    GeometryReader { geo in
                        let width = max(geo.size.width, 1)
                        LinearGradient(
                            colors: shimmerStops,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: trailWidth)
                        .offset(x: phase * (width + trailWidth * 2) - trailWidth)
                        .blendMode(colorScheme == .dark ? .screen : .softLight)
                    }
                    .mask { content }
                    .allowsHitTesting(false)
                }
                .onAppear { startPhaseAnimation() }
                .onChange(of: isActive) { active in
                    if active { startPhaseAnimation() }
                }
                .onChange(of: colorScheme) { _ in
                    if isActive { startPhaseAnimation() }
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
