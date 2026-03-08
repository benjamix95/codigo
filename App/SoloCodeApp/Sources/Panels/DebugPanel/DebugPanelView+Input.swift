import SwiftUI
import Foundation

extension DebugPanelView {
    // MARK: - Chat Input

    var chatInput: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)

                TextField("Ask about the bug…", text: $userInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .focused($isChatInputFocused)
                    .onSubmit { submitInput() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isChatInputFocused ? accent.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )

            Button(action: submitInput) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.secondary.opacity(0.3)
                        : accent,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
            }
            .buttonStyle(.plain)
            .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    func submitInput() {
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSubmitQuestion(userInput)
        userInput = ""
    }

    // MARK: - Empty State

    func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.03))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Helpers

    func timeString(_ date: Date) -> String {
        DebugTimeFormatters.hms.string(from: date)
    }
}

private enum DebugTimeFormatters {
    static let hms: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
