import CoderEngine
import Foundation

extension PipelineIntegrationService {
    /// Meta app-server Codex da eventi raw del bridge Rust (`codex_*`).
    func applyCodexAppServerStreamingMeta(_ p: RawEventPayload) {
        guard p.rawType == "codex_rate_limits_updated" else { return }
        ProviderUsageStore.shared.applyCodexAppServerRateLimitsPayload(p.payload)
    }
}
