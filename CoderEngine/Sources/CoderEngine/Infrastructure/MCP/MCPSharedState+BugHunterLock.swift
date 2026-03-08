import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension MCPSharedState {
    static func withBugHunterFileLock<T>(
        _ operation: () -> T
    ) -> T {
        ensureBugHunterDirectories()
        let lockURL = bugHunterDirectoryPath.appendingPathComponent(".lock")
        let lockPath = lockURL.path

        if !FileManager.default.fileExists(atPath: lockPath) {
            FileManager.default.createFile(atPath: lockPath, contents: Data())
        }

        let descriptor = open(lockPath, O_RDWR)
        guard descriptor >= 0 else {
            return operation()
        }
        defer { close(descriptor) }

        flock(descriptor, LOCK_EX)
        defer { flock(descriptor, LOCK_UN) }
        return operation()
    }
}
