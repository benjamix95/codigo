import Foundation
@testable import CoderEngine

enum PersistenceTestSupport {
    static func enablePersistenceForTests() {
        unsetenv("SOLOCODE_DISABLE_POSTGRES_PERSISTENCE")
        setenv("SOLOCODE_ENABLE_POSTGRES_PERSISTENCE_IN_TESTS", "1", 1)
    }

    static func disablePersistenceForTests() {
        unsetenv("SOLOCODE_ENABLE_POSTGRES_PERSISTENCE_IN_TESTS")
        setenv("SOLOCODE_DISABLE_POSTGRES_PERSISTENCE", "1", 1)
    }

    static func resetPersistenceEnvironment() {
        disablePersistenceForTests()
        try? ManagedPostgresService.shared.shutdownIfRunning()
        try? FileManager.default.removeItem(at: ManagedPostgresConfiguration.default.rootDirectory)
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.verifiedFindingsDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.bugHunterDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.planStateFilePath)
    }

    static func stableDate(_ seconds: TimeInterval = 1_700_000_000) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
