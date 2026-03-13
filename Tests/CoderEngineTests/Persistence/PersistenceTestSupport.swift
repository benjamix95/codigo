import Foundation
@testable import CoderEngine

enum PersistenceTestSupport {
    static func enablePersistenceForTests() {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scpg-\(String(UUID().uuidString.prefix(8)))", isDirectory: true)
        let port = 56000 + Int.random(in: 0...999)
        unsetenv("SOLOCODE_DISABLE_POSTGRES_PERSISTENCE")
        setenv("SOLOCODE_ENABLE_POSTGRES_PERSISTENCE_IN_TESTS", "1", 1)
        setenv(
            "SOLOCODE_POSTGRES_ROOT_DIRECTORY",
            rootDirectory.path,
            1
        )
        setenv(
            "SOLOCODE_POSTGRES_PORT",
            String(port),
            1
        )
    }

    static func disablePersistenceForTests() {
        unsetenv("SOLOCODE_ENABLE_POSTGRES_PERSISTENCE_IN_TESTS")
        setenv("SOLOCODE_DISABLE_POSTGRES_PERSISTENCE", "1", 1)
    }

    static func resetPersistenceEnvironment() {
        let temporaryRoot = temporaryRootDirectory()
        try? ManagedPostgresService.shared.shutdownIfRunning()
        try? FileManager.default.removeItem(at: temporaryRoot)
        unsetenv("SOLOCODE_POSTGRES_ROOT_DIRECTORY")
        unsetenv("SOLOCODE_POSTGRES_PORT")
        disablePersistenceForTests()
        removeIfPresent(ManagedPostgresConfiguration.default.rootDirectory)
        removeIfPresent(MCPSharedState.codeReviewDirectoryPath)
        removeIfPresent(MCPSharedState.verifiedFindingsDirectoryPath)
        removeIfPresent(MCPSharedState.bugHunterDirectoryPath)
        let planStatePath = MCPSharedState.planStateFilePath
        removeIfPresent(planStatePath)
    }

    static func stableDate(_ seconds: TimeInterval = 1_700_000_000) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    static func temporaryRootDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["SOLOCODE_POSTGRES_ROOT_DIRECTORY"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "scpg-\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
    }

    static func temporaryPort() -> Int {
        if let override = ProcessInfo.processInfo.environment["SOLOCODE_POSTGRES_PORT"],
           let port = Int(override) {
            return port
        }
        return 56000 + (Int(ProcessInfo.processInfo.processIdentifier) % 1000)
    }

    private static func removeIfPresent(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
