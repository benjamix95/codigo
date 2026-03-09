import Foundation

extension MCPSharedState {
    static func withBugHunterFileLock<T>(
        _ operation: () -> T
    ) -> T {
        withBugHunterAdvisoryLock(operation)
    }
}
