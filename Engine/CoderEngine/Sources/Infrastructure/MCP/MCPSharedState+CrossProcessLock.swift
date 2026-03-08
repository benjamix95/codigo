import Darwin
import Foundation

extension MCPSharedState {
    static func withCodeReviewFileLock<T>(
        _ body: () -> T
    ) -> T {
        ensureDirectory()
        try? FileManager.default.createDirectory(
            at: codeReviewDirectoryPath,
            withIntermediateDirectories: true
        )
        let lockURL = codeReviewDirectoryPath.appendingPathComponent(".lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            let err = errno
            fatalError(
                "CodeReviewLock: impossibile aprire il file di lock: \(lockURL.path), errno: \(err)"
            )
        }
        defer { close(descriptor) }

        let lockResult = flock(descriptor, LOCK_EX)
        guard lockResult == 0 else {
            let err = errno
            fatalError(
                "CodeReviewLock: flock LOCK_EX fallito su \(lockURL.path), errno: \(err)"
            )
        }
        defer { flock(descriptor, LOCK_UN) }
        return body()
    }
}
