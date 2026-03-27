import XCTest
@testable import CoderIDE

@MainActor
final class CLIAccountUsageLedgerStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CLIAccountUsageLedgerStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testAppendSchedulesBatchedPersistenceAndFlushesLatestSnapshot() async throws {
        let store = CLIAccountUsageLedgerStore(
            userDefaults: defaults,
            key: "ledger.tests",
            saveDelayNanoseconds: 5_000_000
        )

        store.append(accountId: UUID(), provider: .codex, inputTokens: 10, outputTokens: 20, estimatedCostUSD: 0.1)
        store.append(accountId: UUID(), provider: .claude, inputTokens: 30, outputTokens: 40, estimatedCostUSD: 0.2)

        XCTAssertNil(defaults.data(forKey: "ledger.tests"))
        try await Task.sleep(nanoseconds: 20_000_000)

        let data = try XCTUnwrap(defaults.data(forKey: "ledger.tests"))
        let decoded = try JSONDecoder().decode([CLIUsageEvent].self, from: data)
        XCTAssertEqual(decoded.count, 2)
    }

    func testLoadTrimsOversizedLedgerAndPersistsTrimmedSnapshot() async throws {
        let oversized = (0..<5_010).map { index in
            CLIUsageEvent(
                accountId: UUID(),
                provider: .codex,
                inputTokens: index,
                outputTokens: index,
                estimatedCostUSD: Double(index),
                timestamp: .now
            )
        }
        let data = try JSONEncoder().encode(oversized)
        defaults.set(data, forKey: "ledger.tests")

        let store = CLIAccountUsageLedgerStore(
            userDefaults: defaults,
            key: "ledger.tests",
            saveDelayNanoseconds: 0
        )
        await store.flushPendingSavesForTests()

        XCTAssertEqual(store.events.count, 5000)
        let trimmedData = try XCTUnwrap(defaults.data(forKey: "ledger.tests"))
        let trimmed = try JSONDecoder().decode([CLIUsageEvent].self, from: trimmedData)
        XCTAssertEqual(trimmed.count, 5000)
    }
}
