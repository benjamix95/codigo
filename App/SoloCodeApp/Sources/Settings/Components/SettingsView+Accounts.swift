import SwiftUI
import CoderEngine

extension SettingsView {
    @ViewBuilder
    func multiAccountProviderSection(_ provider: CLIProviderKind) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Accounts", systemImage: "person.2")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Toggle("Multi-account", isOn: $cliAccountsStore.multiAccountEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }

                let providerAccounts = cliAccountsStore.accounts(for: provider)
                if providerAccounts.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 20))
                                .foregroundStyle(.tertiary)
                            Text("No accounts yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } else {
                    ForEach(providerAccounts) { account in
                        accountCard(account, provider: provider)
                    }
                }

                Button {
                    let account = cliAccountsStore.addAccountQuick(provider: provider)
                    pendingLoginAccountIds.insert(account.id)
                    loginSheetAccount = account
                } label: {
                    Label("Add Account", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(4)
        } label: {
            Text("\(provider.displayName) Accounts")
        }
    }

    @ViewBuilder
    func accountCard(_ account: CLIAccount, provider: CLIProviderKind) -> some View {
        let isConnected = accountAuthStatus(account).isLoggedIn
        let identity = CLIAccountAuthDetector.identity(account: account)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                accountAvatar(account)

                TextField("Label", text: Binding(
                    get: { account.label },
                    set: { var u = account; u.label = $0; cliAccountsStore.update(u) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))

                Spacer()

                Toggle("", isOn: Binding(
                    get: { account.isEnabled },
                    set: { var u = account; u.isEnabled = $0; cliAccountsStore.update(u) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            if let displayName = identity?.displayName, !displayName.isEmpty {
                Text(displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let email = identity?.email, !email.isEmpty {
                Text(email)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                statusBadge(connected: isConnected, label: accountStatusLabel(account))

                Spacer()

                let day = cliUsageLedger.totals(accountId: account.id, period: .day)
                let month = cliUsageLedger.totals(accountId: account.id, period: .month)
                Text("$\(day.cost, specifier: "%.2f")/d")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Text("$\(month.cost, specifier: "%.2f")/m")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }

            HStack(spacing: 6) {
                if !isConnected {
                    Button("Sign In") {
                        loginSheetAccount = account
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("Disconnect") { disconnectAccount(account) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Spacer()

                Button(role: .destructive) {
                    showDeleteConfirmation = account.id
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .alert("Delete Account",
                       isPresented: Binding(
                        get: { showDeleteConfirmation == account.id },
                        set: { if !$0 { showDeleteConfirmation = nil } }
                       )
                ) {
                    Button("Delete", role: .destructive) {
                        cliAccountsStore.delete(accountId: account.id)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Remove \"\(account.label)\"? This will delete the profile directory and credentials.")
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isConnected ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
    func accountAvatar(_ account: CLIAccount) -> some View {
        let fallback = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = CLIAccountAuthDetector.identity(account: account)
        let displayName = identity?.displayName ?? ""
        let email = identity?.email ?? ""
        let seed = !displayName.isEmpty ? displayName : (email.isEmpty ? fallback : email)
        let initial = seed.isEmpty ? "?" : String(seed.prefix(1)).uppercased()

        return ZStack {
            Circle()
                .fill(providerAvatarColor(account.provider))
                .frame(width: 28, height: 28)
            Text(initial)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
    func providerAvatarColor(_ provider: CLIProviderKind) -> Color {
        switch provider {
        case .codex:
            return .green
        case .claude:
            return .orange
        case .gemini:
            return .blue
        }
    }
    func accountStatusLabel(_ account: CLIAccount) -> String {
        let auth = accountAuthStatus(account)
        if account.health.isExhaustedLocally { return "Exhausted (local limit)" }
        if let until = account.health.cooldownUntil, until > Date() {
            return "Cooldown until \(until.formatted(date: .omitted, time: .shortened))"
        }
        switch auth {
        case .loggedIn(let method):
            return "Connected (\(method.rawValue))"
        case .notLoggedIn:
            return "Not connected"
        case .notInstalled:
            return "CLI not installed"
        case .error(let message):
            return "Auth error: \(message)"
        }
    }
    func codexCreditsLabel() -> String {
        guard let usage = providerUsageStore.codexUsage, let balance = usage.creditsBalance else { return "Credits: N/A" }
        let currency = usage.creditsCurrency ?? "USD"
        return String(format: "Credits: %.2f %@", balance, currency)
    }
    func connectToClaude() {
        guard ClaudeDetector.findClaudePath(customPath: claudePath.isEmpty ? nil : claudePath) != nil else { return }
        let existingAccounts = cliAccountsStore.accounts(for: .claude)
        if let first = existingAccounts.first {
            loginSheetAccount = first
        } else {
            let account = cliAccountsStore.addAccountQuick(provider: .claude)
            pendingLoginAccountIds.insert(account.id)
            loginSheetAccount = account
        }
    }
    func connectToCodex() {
        guard codexState.status.path != nil || CodexDetector.findCodexPath(customPath: codexPath.isEmpty ? nil : codexPath) != nil else { return }
        if codexState.status.isLoggedIn {
            syncCodex()
        } else {
            let existingAccounts = cliAccountsStore.accounts(for: .codex)
            if let first = existingAccounts.first {
                loginSheetAccount = first
            } else {
                let account = cliAccountsStore.addAccountQuick(provider: .codex)
                pendingLoginAccountIds.insert(account.id)
                loginSheetAccount = account
            }
        }
    }
    func handleLoginSheetDismiss(for account: CLIAccount) {
        defer {
            pendingLoginAccountIds.remove(account.id)
            syncProviders()
        }
        guard cliAccountsStore.accounts.contains(where: { $0.id == account.id }) else { return }

        let status = accountAuthStatus(account)
        cliAccountsStore.updateAuthStatus(accountId: account.id, status: status)

        if status.isLoggedIn {
            let primaryId = cliAccountsStore.finalizePostLogin(
                accountId: account.id,
                preferredActiveAccountId: CLIAccountRouter.shared.currentActiveAccountByProvider[account.provider]
            ) ?? account.id
            CLIAccountRouter.shared.markAccountSelected(
                accountId: primaryId,
                provider: account.provider,
                reason: "login_success"
            )
            return
        }

        if pendingLoginAccountIds.contains(account.id) {
            cliAccountsStore.delete(accountId: account.id)
        }
    }
    func disconnectAccount(_ account: CLIAccount) {
        accountLoginCoordinator.disconnect(account: account)
        let status = accountAuthStatus(account)
        cliAccountsStore.updateAuthStatus(accountId: account.id, status: status)
    }
    func accountAuthStatus(_ account: CLIAccount) -> CLIAccountAuthStatus {
        CLIAccountAuthDetector.detect(account: account, providerPath: providerPath(for: account.provider))
    }
    func providerPath(for provider: CLIProviderKind) -> String? {
        switch provider {
        case .codex: return codexPath
        case .claude: return claudePath
        case .gemini: return geminiCliPath
        }
    }
}
