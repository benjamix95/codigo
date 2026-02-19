import Foundation
import CoderEngine

final class CLIMultiAccountProviderAdapter: LLMProvider, @unchecked Sendable {
    let id: String
    let displayName: String

    private let providerKind: CLIProviderKind
    private let router: CLIAccountRouter
    private let accountsStore: CLIAccountsStore
    private let makeProvider: (CLIAccount, [String: String]) -> any LLMProvider

    init(
        providerKind: CLIProviderKind,
        id: String,
        displayName: String,
        router: CLIAccountRouter,
        accountsStore: CLIAccountsStore,
        makeProvider: @escaping (CLIAccount, [String: String]) -> any LLMProvider
    ) {
        self.providerKind = providerKind
        self.id = id
        self.displayName = displayName
        self.router = router
        self.accountsStore = accountsStore
        self.makeProvider = makeProvider
    }

    func isAuthenticated() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: "CoderIDE.cliAccounts"),
              let decoded = try? JSONDecoder().decode([CLIAccount].self, from: data) else {
            return false
        }
        return decoded.contains { $0.provider == providerKind && $0.isEnabled }
    }

    func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]?) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var attempted = Set<UUID>()
                var account = await MainActor.run { router.selectAccount(for: providerKind) }
                var lastErrorMessage = ""

                while let selected = account, !attempted.contains(selected.id) {
                    attempted.insert(selected.id)
                    await MainActor.run {
                        router.markAccountSelected(accountId: selected.id, provider: providerKind, reason: nil)
                    }
                    let secret = await MainActor.run { accountsStore.secret(for: selected.id) }
                    let env = CLIProfileProvisioner.environmentOverrides(provider: providerKind, profilePath: selected.profilePath, secret: secret)
                    let provider = makeProvider(selected, env)

                    do {
                        let stream = try await provider.send(prompt: prompt, context: context, imageURLs: imageURLs)
                        for try await event in stream {
                            if case .raw(let type, let payload) = event, type == "usage" {
                                let input = Int(payload["input_tokens"] ?? "0") ?? 0
                                let output = Int(payload["output_tokens"] ?? "0") ?? 0
                                let cost = ModelPricing.estimatedCost(inputTokens: input, outputTokens: output, model: payload["model"] ?? id)
                                await MainActor.run {
                                    router.markUsage(accountId: selected.id, provider: providerKind, inputTokens: input, outputTokens: output, estimatedCost: cost)
                                    Task { await AccountUsageDashboardStore.shared.refresh() }
                                }
                            }
                            if case .error(let message) = event {
                                lastErrorMessage = message
                            }
                            continuation.yield(event)
                        }
                        continuation.finish()
                        return
                    } catch {
                        let message = lastErrorMessage.isEmpty ? error.localizedDescription : lastErrorMessage
                        let classified = CLIErrorClassifier.classify(providerId: id, message: message)
                        await MainActor.run {
                            router.markProviderError(
                                accountId: selected.id,
                                provider: providerKind,
                                classifiedError: CLIClassifiedFailure(
                                    isQuotaExhaustion: classified.isQuotaExhaustion,
                                    isRateLimited: classified.isRateLimited,
                                    retryAfterSeconds: classified.retryAfterSeconds,
                                    normalizedCode: classified.normalizedCode
                                )
                            )
                            Task { await AccountUsageDashboardStore.shared.refresh() }
                        }

                        if classified.isQuotaExhaustion || classified.isRateLimited {
                            await MainActor.run {
                                router.markAccountSelected(
                                    accountId: selected.id,
                                    provider: providerKind,
                                    reason: classified.normalizedCode
                                )
                            }
                            account = await MainActor.run { router.nextAvailableAccount(after: selected.id, provider: providerKind) }
                            continue
                        }
                        continuation.yield(.error(error.localizedDescription))
                        continuation.finish(throwing: error)
                        return
                    }
                }

                continuation.yield(.error("Tutti gli account \(providerKind.displayName) sono esauriti o non disponibili."))
                continuation.finish(throwing: CoderEngineError.notAuthenticated)
            }
        }
    }
}
