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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trailWidth: CGFloat = 96
    private let sweepPeriod: TimeInterval = 1.05

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

    @ViewBuilder
    func body(content: Content) -> some View {
        // TimelineView: in ScrollView/list la repeatForever su @State spesso non ridisegna;
        // il tick del timeline aggiorna anche quando il padre applica Equatable o coalescing.
        if isActive && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 36.0)) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let phase = CGFloat(
                    elapsed.truncatingRemainder(dividingBy: sweepPeriod) / sweepPeriod
                )
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
