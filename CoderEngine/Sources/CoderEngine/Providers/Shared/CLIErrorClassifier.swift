import Foundation

public struct CLIErrorClassification: Sendable {
    public let isQuotaExhaustion: Bool
    public let isRateLimited: Bool
    public let retryAfterSeconds: Int?
    public let normalizedCode: String

    public init(isQuotaExhaustion: Bool, isRateLimited: Bool, retryAfterSeconds: Int?, normalizedCode: String) {
        self.isQuotaExhaustion = isQuotaExhaustion
        self.isRateLimited = isRateLimited
        self.retryAfterSeconds = retryAfterSeconds
        self.normalizedCode = normalizedCode
    }
}

public enum CLIErrorClassifier {
    public static func classify(providerId: String, message: String) -> CLIErrorClassification {
        let lower = message.lowercased()
        let isQuota = lower.contains("quota") || lower.contains("insufficient") || lower.contains("credit") || lower.contains("billing")
        let isRate = lower.contains("rate limit") || lower.contains("too many requests") || lower.contains("429")

        let retryAfter: Int? = {
            let regex = try? NSRegularExpression(pattern: "retry[- ]?after[: ]+([0-9]+)", options: .caseInsensitive)
            guard let regex,
                  let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  let range = Range(match.range(at: 1), in: lower) else { return nil }
            return Int(lower[range])
        }()

        let code: String
        if isQuota {
            code = "quota_exhausted"
        } else if isRate {
            code = "rate_limited"
        } else {
            code = "generic_error"
        }

        return CLIErrorClassification(
            isQuotaExhaustion: isQuota,
            isRateLimited: isRate,
            retryAfterSeconds: retryAfter,
            normalizedCode: "\(providerId):\(code)"
        )
    }
}
