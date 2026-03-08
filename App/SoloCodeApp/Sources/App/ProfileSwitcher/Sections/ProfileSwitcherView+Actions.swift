import SwiftUI
import CoderEngine

extension ProfileSwitcherView {
    func startRename(_ account: CLIAccount) {
        renamingAccountId = account.id
        renameDraft = account.label
    }

    func saveRename(_ account: CLIAccount) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = account
        updated.label = trimmed
        accountsStore.update(updated)
        renamingAccountId = nil
        renameDraft = ""
    }

    func handleLoginSheetDismiss(for account: CLIAccount) {
        defer {
            pendingLoginAccountIds.remove(account.id)
            router.bootstrapActiveSelectionsIfNeeded()
        }
        guard accountsStore.accounts.contains(where: { $0.id == account.id }) else { return }
        let status = CLIAccountAuthDetector.detect(
            account: account,
            providerPath: resolveProviderPath(account.provider)
        )
        CLIAccountsStore.shared.updateAuthStatus(accountId: account.id, status: status)
        if status.isLoggedIn {
            let primaryId = CLIAccountsStore.shared.finalizePostLogin(
                accountId: account.id,
                preferredActiveAccountId: router.currentActiveAccountByProvider[account.provider]
            ) ?? account.id
            router.markAccountSelected(
                accountId: primaryId,
                provider: account.provider,
                reason: "login_success"
            )
            return
        }
        if pendingLoginAccountIds.contains(account.id) {
            CLIAccountsStore.shared.delete(accountId: account.id)
        }
    }
}
