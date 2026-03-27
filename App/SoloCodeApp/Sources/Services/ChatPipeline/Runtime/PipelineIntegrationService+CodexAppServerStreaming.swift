import CoderEngine
import Foundation

extension PipelineIntegrationService {
    /// Meta app-server Codex da eventi raw del bridge Rust (`codex_*`).
    func applyCodexAppServerStreamingMeta(_ p: RawEventPayload) {
        // #region agent log
        if p.rawType == "codex_rate_limits_updated" || p.rawType == "codex_thread_token_usage" {
            CursorSessionDebugNDJSON.append(
                hypothesisId: "H4",
                location: "PipelineIntegrationService+CodexAppServerStreaming",
                message: "codex_stream_meta",
                data: [
                    "rawType": p.rawType,
                    "payloadKeyCount": String(p.payload.count),
                ]
            )
        }
        // #endregion
        guard p.rawType == "codex_rate_limits_updated" else { return }
        ProviderUsageStore.shared.applyCodexAppServerRateLimitsPayload(p.payload)
    }
}
