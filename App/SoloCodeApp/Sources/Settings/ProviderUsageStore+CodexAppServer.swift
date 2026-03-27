import CoderEngine
import Foundation

extension ProviderUsageStore {
    /// Aggiorna lo snapshot Codex da notifica streaming `codex_rate_limits_updated` (flat + `rateLimits_json`).
    func applyCodexAppServerRateLimitsPayload(_ payload: [String: String]) {
        // #region agent log
        let keysSnippet = payload.keys.sorted().prefix(12).joined(separator: ",")
        // #endregion
        guard let jsonStr = payload["rateLimits_json"] ?? payload["rateLimits"],
              let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // #region agent log
            CursorSessionDebugNDJSON.append(
                hypothesisId: "H3",
                location: "ProviderUsageStore+CodexAppServer",
                message: "rate_limits_parse_skipped",
                data: ["payloadKeys": keysSnippet]
            )
            // #endregion
            return
        }
        guard let usage = CodexUsageFetcher.codexUsage(fromAppServerRateLimitsWire: ["rateLimits": obj]) else {
            // #region agent log
            CursorSessionDebugNDJSON.append(
                hypothesisId: "H3",
                location: "ProviderUsageStore+CodexAppServer",
                message: "codex_usage_nil",
                data: ["payloadKeys": keysSnippet]
            )
            // #endregion
            return
        }
        codexUsage = usage
        codexUsageMessage = nil
        // #region agent log
        CursorSessionDebugNDJSON.append(
            hypothesisId: "H3",
            location: "ProviderUsageStore+CodexAppServer",
            message: "codex_usage_applied",
            data: [
                "p5": usage.fiveHourPct.map { String(format: "%.1f", $0) } ?? "nil",
                "pw": usage.weeklyPct.map { String(format: "%.1f", $0) } ?? "nil",
                "r5": usage.resetFiveH ?? "nil",
                "rw": usage.resetWeekly ?? "nil",
            ]
        )
        // #endregion
    }
}
