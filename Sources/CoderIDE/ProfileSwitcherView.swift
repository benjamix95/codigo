import SwiftUI
import CoderEngine

/// Compact profile avatar button for the sidebar footer.
/// Shows the active account's initial/avatar. Clicking opens a popover
/// listing all accounts grouped by provider for quick switching.
struct ProfileSwitcherView: View {
    @StateObject private var accountsStore = CLIAccountsStore.shared
    @StateObject private var router = CLIAccountRouter.shared

    @State private var showPopover = false
    @State private var addAccountProvider: CLIProviderKind?
    @State private var loginSheetAccount: CLIAccount?

    /// The "primary" active account — first provider that has an active selection.
    private var primaryActiveAccount: CLIAccount? {
        for provider in CLIProviderKind.allCases {
            if let accountId = router.currentActiveAccountByProvider[provider],
               let account = accountsStore.accounts.first(where: { $0.id == accountId }) {
                return account
            }
        }
        return nil
    }

    /// Providers that have at least one enabled account.
    private var activeProviders: [CLIProviderKind] {
        CLIProviderKind.allCases.filter { provider in
            accountsStore.accounts.contains { $0.provider == provider && $0.isEnabled }
        }
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            avatarCircle(for: primaryActiveAccount)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            accountListPopover
        }
        .sheet(item: $loginSheetAccount) { account in
            CLIAccountLoginSheet(
                account: account,
                providerPath: resolveProviderPath(account.provider)
            )
        }
    }

    // MARK: - Avatar

    private func avatarCircle(for account: CLIAccount?) -> some View {
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

    private func smallAvatar(for account: CLIAccount) -> some View {
        ZStack {
            Circle()
                .fill(avatarColor(for: account))
                .frame(width: 20, height: 20)
            Text(avatarInitial(for: account))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func avatarInitial(for account: CLIAccount?) -> String {
        guard let account else { return "?" }
        let label = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = label.first {
            return String(first).uppercased()
        }
        return account.provider.rawValue.prefix(1).uppercased()
    }

    private func avatarColor(for account: CLIAccount?) -> Color {
        guard let account else { return .gray }
        return providerColor(account.provider)
    }

    private func providerColor(_ provider: CLIProviderKind) -> Color {
        switch provider {
        case .codex: return .green
        case .claude: return .orange
        case .gemini: return .blue
        }
    }

    // MARK: - Popover

    private var accountListPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Accounts")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            if accountsStore.accounts.filter({ $0.isEnabled }).isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                    Text("No accounts configured")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                // Group by provider
                ForEach(CLIProviderKind.allCases) { provider in
                    let providerAccounts = accountsStore.accounts(for: provider).filter { $0.isEnabled }
                    if !providerAccounts.isEmpty {
                        providerSection(provider: provider, accounts: providerAccounts)
                    }
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Add account quick-action
            Menu {
                ForEach(CLIProviderKind.allCases) { provider in
                    Button {
                        let account = accountsStore.addAccountQuick(provider: provider)
                        showPopover = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            loginSheetAccount = account
                        }
                    } label: {
                        Label(provider.displayName, systemImage: providerIcon(provider))
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 11))
                    Text("Add Account")
                        .font(.system(size: 12))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            // Manage in settings
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .font(.system(size: 10))
                Text("Manage in Settings")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                showPopover = false
                NotificationCenter.default.post(name: .openSettingsToAccounts, object: nil)
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 220, maxWidth: 280)
    }

    private func providerSection(provider: CLIProviderKind, accounts: [CLIAccount]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Provider header
            HStack(spacing: 6) {
                Circle()
                    .fill(providerColor(provider))
                    .frame(width: 6, height: 6)
                Text(provider.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ForEach(accounts) { account in
                accountRow(account)
            }
        }
    }

    private func accountRow(_ account: CLIAccount) -> some View {
        let isActive = router.currentActiveAccountByProvider[account.provider] == account.id

        return Button {
            router.markAccountSelected(
                accountId: account.id,
                provider: account.provider,
                reason: "manual_switch"
            )
            showPopover = false
        } label: {
            HStack(spacing: 8) {
                smallAvatar(for: account)

                Text(account.label)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)

                Spacer()

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    // MARK: - Helpers

    private func providerIcon(_ provider: CLIProviderKind) -> String {
        switch provider {
        case .codex: return "terminal"
        case .claude: return "brain.head.profile"
        case .gemini: return "sparkles"
        }
    }

    private func resolveProviderPath(_ provider: CLIProviderKind) -> String? {
        switch provider {
        case .codex:
            let custom = UserDefaults.standard.string(forKey: "codex_path")
            return CLIAccountAuthDetector.resolveExecutable(provider: .codex, providerPath: custom)
        case .claude:
            let custom = UserDefaults.standard.string(forKey: "claude_path")
            return CLIAccountAuthDetector.resolveExecutable(provider: .claude, providerPath: custom)
        case .gemini:
            let custom = UserDefaults.standard.string(forKey: "gemini_cli_path")
            return CLIAccountAuthDetector.resolveExecutable(provider: .gemini, providerPath: custom)
        }
    }
}

// MARK: - Notification for opening settings to accounts tab

extension Notification.Name {
    static let openSettingsToAccounts = Notification.Name("openSettingsToAccounts")
}
