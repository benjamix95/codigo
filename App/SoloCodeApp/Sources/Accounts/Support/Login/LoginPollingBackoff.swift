import Foundation

enum LoginPollingBackoff {
    static func seconds(
        forAttempt attempt: Int,
        baseSeconds: Int = 2,
        rampEveryAttempts: Int = 3,
        maxSeconds: Int = 8
    ) -> Int {
        let normalizedBase = max(0, baseSeconds)
        guard normalizedBase > 0 else { return 0 }
        let ramp = max(1, rampEveryAttempts)
        let cappedMax = max(normalizedBase, maxSeconds)
        return min(normalizedBase + (max(0, attempt) / ramp), cappedMax)
    }
}
