import CoderEngine
import Foundation

extension ProviderUsageStore {
    /// Aggiorna lo snapshot Codex da notifica streaming `codex_rate_limits_updated` (flat + `rateLimits_json`).
    func applyCodexAppServerRateLimitsPayload(_ payload: [String: String]) {
        guard let jsonStr = payload["rateLimits_json"] ?? payload["rateLimits"],
              let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        guard let usage = CodexUsageFetcher.codexUsage(fromAppServerRateLimitsWire: ["rateLimits": obj]) else {
            return
        }
        codexUsage = usage
        codexUsageMessage = nil
    }
}
