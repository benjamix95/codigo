import SwiftUI

extension EditorPlaceholderView {
    // MARK: - Error / Status
    func errorBanner(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Colors.error)
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.Colors.error)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DesignSystem.Colors.error.opacity(0.08))
    }

    func statusBar(_ feedback: String) -> some View {
        HStack {
            Text(feedback)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(saveFeedbackIsError ? DesignSystem.Colors.error : .secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(DesignSystem.Colors.backgroundPrimary.opacity(0.5))
    }
}
