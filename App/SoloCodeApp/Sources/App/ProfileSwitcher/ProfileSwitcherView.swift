import SwiftUI
import CoderEngine

/// Compact profile avatar button for the sidebar footer.
/// Shows the active account's initial/avatar. Clicking opens a popover
/// listing all accounts grouped by provider for quick switching.
struct ProfileSwitcherView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @StateObject var accountsStore = CLIAccountsStore.shared
    @StateObject var router = CLIAccountRouter.shared

    @State var showPopover = false
    @State var loginSheetAccount: CLIAccount?
    @State var pendingLoginAccountIds: Set<UUID> = []
    @State var renamingAccountId: UUID?
    @State var renameDraft = ""

    /// The "primary" active account — first provider that has an active selection.
    var primaryActiveAccount: CLIAccount? {
        for provider in CLIProviderKind.allCases {
            if let account = router.activeAccount(for: provider) {
                return account
            }
        }
        return nil
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 8) {
                avatarCircle(for: primaryActiveAccount)
                VStack(alignment: .leading, spacing: 1) {
                    Text(primaryTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(primarySubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            accountListPopover
        }
        .sheet(item: $loginSheetAccount) { account in
            CLIAccountLoginSheet(
                account: account,
                providerPath: resolveProviderPath(account.provider),
                onDismiss: {
                    handleLoginSheetDismiss(for: account)
                }
            )
        }
        .onAppear {
            accountsStore.bootstrapAccountsIfNeeded()
            router.bootstrapActiveSelectionsIfNeeded()
        }
        .onChange(of: accountsStore.accounts) { _ in
            router.bootstrapActiveSelectionsIfNeeded()
        }
    }
}
