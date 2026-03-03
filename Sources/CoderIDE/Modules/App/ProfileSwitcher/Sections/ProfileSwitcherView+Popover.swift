import SwiftUI
import CoderEngine

extension ProfileSwitcherView {
    // MARK: - Popover

    var accountListPopover: some View {
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
                ForEach(CLIProviderKind.allCases) { provider in
                    let providerAccounts = accountsStore.accounts(for: provider).filter { $0.isEnabled }
                    if !providerAccounts.isEmpty {
                        providerSection(provider: provider, accounts: providerAccounts)
                    }
                }
            }

            Divider()
                .padding(.vertical, 4)

            Menu {
                ForEach(CLIProviderKind.allCases) { provider in
                    Button {
                        let account = accountsStore.addAccountQuick(provider: provider)
                        pendingLoginAccountIds.insert(account.id)
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

    func providerSection(provider: CLIProviderKind, accounts: [CLIAccount]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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

    func accountRow(_ account: CLIAccount) -> some View {
        let isActive = router.currentActiveAccountByProvider[account.provider] == account.id
        let identity = CLIAccountAuthDetector.identity(account: account)
        let isRenaming = renamingAccountId == account.id

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                guard !isRenaming else { return }
                router.markAccountSelected(
                    accountId: account.id,
                    provider: account.provider,
                    reason: "manual_switch"
                )
                providerRegistry.selectedProviderId = account.provider.providerId
                Task { await AccountUsageDashboardStore.shared.refresh() }
                showPopover = false
            } label: {
                HStack(spacing: 8) {
                    smallAvatar(for: account)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.label)
                            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                            .lineLimit(1)
                        if let displayName = identity?.displayName, !displayName.isEmpty {
                            Text(displayName)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if let method = identity?.authMethod {
                            Text(method.rawValue)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Not connected")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

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

            if account.provider == .claude {
                Button {
                    startRename(account)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Rename account")
            }

            if isRenaming {
                HStack(spacing: 6) {
                    TextField("Account label", text: $renameDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    Button("Save") {
                        saveRename(account)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel") {
                        renamingAccountId = nil
                        renameDraft = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
    }
}
