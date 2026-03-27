import Foundation

struct CLIUsageEvent: Codable {
    let accountId: UUID
    let provider: CLIProviderKind
    let inputTokens: Int
    let outputTokens: Int
    let estimatedCostUSD: Double
    let timestamp: Date
}

@MainActor
final class CLIAccountUsageLedgerStore: ObservableObject {
    static let shared = CLIAccountUsageLedgerStore()
    @Published private(set) var events: [CLIUsageEvent] = []
    private let key: String
    private let userDefaults: UserDefaults
    private let saveDelayNanoseconds: UInt64
    private var pendingSaveTask: Task<Void, Never>?

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "CoderIDE.cliAccountUsageLedger",
        saveDelayNanoseconds: UInt64 = 150_000_000
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.saveDelayNanoseconds = saveDelayNanoseconds
        load()
    }

    func append(accountId: UUID, provider: CLIProviderKind, inputTokens: Int, outputTokens: Int, estimatedCostUSD: Double) {
        let event = CLIUsageEvent(
            accountId: accountId,
            provider: provider,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCostUSD: estimatedCostUSD,
            timestamp: .now
        )
        events.append(event)
        if events.count > 5000 {
            events = Array(events.suffix(5000))
        }
        scheduleSave()
    }

    func totals(accountId: UUID, period: Calendar.Component) -> (cost: Double, tokens: Int) {
        let calendar = Calendar.current
        let now = Date()
        let filtered = events.filter { e in
            guard e.accountId == accountId else { return false }
            switch period {
            case .day:
                return calendar.isDate(e.timestamp, inSameDayAs: now)
            case .weekOfYear:
                return calendar.component(.yearForWeekOfYear, from: e.timestamp) == calendar.component(.yearForWeekOfYear, from: now)
                    && calendar.component(.weekOfYear, from: e.timestamp) == calendar.component(.weekOfYear, from: now)
            case .month:
                return calendar.component(.year, from: e.timestamp) == calendar.component(.year, from: now)
                    && calendar.component(.month, from: e.timestamp) == calendar.component(.month, from: now)
            default:
                return false
            }
        }
        let cost = filtered.reduce(0.0) { $0 + $1.estimatedCostUSD }
        let tokens = filtered.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
        return (cost, tokens)
    }

    func flushPendingSavesForTests() async {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        persist(events)
    }

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        let snapshot = events
        let userDefaults = self.userDefaults
        let key = self.key
        let delay = saveDelayNanoseconds
        pendingSaveTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                userDefaults.set(data, forKey: key)
            }
        }
    }

    private func persist(_ snapshot: [CLIUsageEvent]) {
        if let data = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CLIUsageEvent].self, from: data) else {
            return
        }
        if decoded.count > 5000 {
            events = Array(decoded.suffix(5000))
            persist(events)
            return
        }
        events = decoded
    }
}
