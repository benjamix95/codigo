import SwiftUI
import CoderEngine

extension ProfileSwitcherView {
    // MARK: - Avatar

    func avatarCircle(for account: CLIAccount?) -> some View {
        ZStack {
            Circle()
                .fill(avatarColor(for: account))
                .frame(width: 24, height: 24)

            Text(avatarInitial(for: account))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .overlay(
            Circle()
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
    }

    func smallAvatar(for account: CLIAccount) -> some View {
        ZStack {
            Circle()
                .fill(avatarColor(for: account))
                .frame(width: 20, height: 20)
            Text(avatarInitial(for: account))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    func avatarInitial(for account: CLIAccount?) -> String {
        guard let account else { return "?" }
        let label = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = label.first {
            return String(first).uppercased()
        }
        return account.provider.rawValue.prefix(1).uppercased()
    }

    func avatarColor(for account: CLIAccount?) -> Color {
        guard let account else { return .gray }
        return providerColor(account.provider)
    }

    func providerColor(_ provider: CLIProviderKind) -> Color {
        switch provider {
        case .codex: return .green
        case .claude: return .orange
        case .gemini: return .blue
        }
    }
}
