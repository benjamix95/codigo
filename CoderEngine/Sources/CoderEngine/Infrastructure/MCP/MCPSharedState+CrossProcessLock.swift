import Darwin
import Foundation

extension MCPSharedState {
    static func withCodeReviewFileLock<T>(
        _ body: () -> T
    ) -> T {
        ensureDirectory()
        if !FileManager.default.fileExists(atPath: codeReviewDirectoryPath.path) {
            try? FileManager.default.createDirectory(
                at: codeReviewDirectoryPath,
                withIntermediateDirectories: true
            )
        }
        let lockURL = codeReviewDirectoryPath.appendingPathComponent(".lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            return body()
        }
        flock(descriptor, LOCK_EX)
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        return body()
    }
}
