import SwiftUI

func renderedCircularProgress(_ progress: Double) -> Double {
    let clamped = min(1, max(0, progress))
    if clamped > 0 && clamped < 0.01 {
        return 0.01
    }
    return clamped
}

struct CircularProgressView: View {
    let progress: Double
    let lineWidth: CGFloat
    let size: CGFloat

    init(progress: Double, lineWidth: CGFloat = 3, size: CGFloat = 24) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.size = size
    }

    private var progressColor: Color {
        if progress >= 0.9 { return DesignSystem.Colors.error }
        if progress >= 0.7 { return DesignSystem.Colors.warning }
        return DesignSystem.Colors.success
    }

    var body: some View {
        let renderedProgress = renderedCircularProgress(progress)
        ZStack {
            Circle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: renderedProgress)
                .stroke(progressColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}
