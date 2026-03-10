import Darwin
import Foundation

extension MCPSharedState {
    final class EmergencyLockDescriptorReserve: @unchecked Sendable {
        private let lock = NSLock()
        private let reservePath: String
        private let reserveFlags: Int32
        private var descriptor: Int32

        init(
            reservePath: String = "/dev/null",
            reserveFlags: Int32 = O_RDONLY
        ) {
            self.reservePath = reservePath
            self.reserveFlags = reserveFlags
            self.descriptor = open(reservePath, reserveFlags)
        }

        func releaseDescriptor() -> Bool {
            lock.lock()
            let descriptor = self.descriptor
            self.descriptor = -1
            lock.unlock()

            guard descriptor >= 0 else {
                return false
            }
            close(descriptor)
            return true
        }

        func replenishIfNeeded() {
            lock.lock()
            guard descriptor < 0 else {
                lock.unlock()
                return
            }
            descriptor = open(reservePath, reserveFlags)
            lock.unlock()
        }
    }

    enum AdvisoryFileLockAcquisition {
        case locked(Int32, EmergencyLockDescriptorReserve?)
        case fallback(Int32)
    }

    private static let codeReviewFallbackLock = NSRecursiveLock()
    private static let bugHunterFallbackLock = NSRecursiveLock()
    private static let codeReviewEmergencyLockReserve =
        EmergencyLockDescriptorReserve()
    private static let bugHunterEmergencyLockReserve =
        EmergencyLockDescriptorReserve()

    static func withCodeReviewFileLock<T>(
        _ body: () -> T
    ) -> T {
        withAdvisoryFileLock(
            label: "CodeReviewLock",
            lockURL: codeReviewDirectoryPath.appendingPathComponent(".lock"),
            createMode: S_IRUSR | S_IWUSR,
            fallbackLock: codeReviewFallbackLock,
            emergencyReserve: codeReviewEmergencyLockReserve,
            ensureLockDirectory: {
                ensureDirectory()
                try? FileManager.default.createDirectory(
                    at: codeReviewDirectoryPath,
                    withIntermediateDirectories: true
                )
            },
            body: body
        )
    }

    static func withBugHunterAdvisoryLock<T>(
        _ body: () -> T
    ) -> T {
        withAdvisoryFileLock(
            label: "BugHunterLock",
            lockURL: bugHunterDirectoryPath.appendingPathComponent(".lock"),
            createMode: 0o644,
            fallbackLock: bugHunterFallbackLock,
            emergencyReserve: bugHunterEmergencyLockReserve,
            ensureLockDirectory: {
                ensureBugHunterDirectories()
            },
            body: body
        )
    }

    static func withAdvisoryFileLock<T>(
        label: String,
        lockURL: URL,
        createMode: mode_t,
        fallbackLock: NSRecursiveLock,
        emergencyReserve: EmergencyLockDescriptorReserve = EmergencyLockDescriptorReserve(),
        ensureLockDirectory: () -> Void,
        acquireLock: (() -> AdvisoryFileLockAcquisition)? = nil,
        body: () -> T
    ) -> T {
        fallbackLock.lock()
        defer { fallbackLock.unlock() }

        let reentrancyKey = advisoryLockReentrancyKey(for: lockURL)
        let reentrancyDepth = incrementAdvisoryLockReentrancy(for: reentrancyKey)
        defer { decrementAdvisoryLockReentrancy(for: reentrancyKey) }

        if reentrancyDepth > 1 {
            return body()
        }

        let acquisition = acquireLock?() ?? acquireAdvisoryFileLock(
            lockURL: lockURL,
            createMode: createMode,
            ensureLockDirectory: ensureLockDirectory,
            emergencyReserve: emergencyReserve
        )

        switch acquisition {
        case .locked(let descriptor, let releasedReserve):
            defer { close(descriptor) }
            defer { flock(descriptor, LOCK_UN) }
            defer { releasedReserve?.replenishIfNeeded() }
            return body()
        case .fallback(let err):
            if acquireLock != nil {
                print(
                    "[MCPSharedState] ⚠️ \(label): test fallback locale per \(lockURL.path), errno: \(err)"
                )
                ensureLockDirectory()
                return body()
            }
            fatalError(
                "\(label): impossibile acquisire un advisory lock crash-safe su \(lockURL.path), errno: \(err)"
            )
        }
    }

    static func acquireAdvisoryFileLock(
        lockURL: URL,
        createMode: mode_t,
        ensureLockDirectory: () -> Void,
        emergencyReserve: EmergencyLockDescriptorReserve
    ) -> AdvisoryFileLockAcquisition {
        var lastErr: Int32 = 0

        for _ in 0..<2 {
            ensureLockDirectory()
            var releasedReserve: EmergencyLockDescriptorReserve?
            var descriptor = open(lockURL.path, O_CREAT | O_RDWR, createMode)
            if descriptor < 0, shouldUseEmergencyReserve(errno) {
                if emergencyReserve.releaseDescriptor() {
                    releasedReserve = emergencyReserve
                    descriptor = open(lockURL.path, O_CREAT | O_RDWR, createMode)
                }
            }
            guard descriptor >= 0 else {
                lastErr = errno
                releasedReserve?.replenishIfNeeded()
                if lastErr == ENOENT {
                    continue
                }
                return .fallback(lastErr)
            }

            while true {
                let lockResult = flock(descriptor, LOCK_EX)
                if lockResult == 0 {
                    return .locked(descriptor, releasedReserve)
                }

                lastErr = errno
                if lastErr == EINTR {
                    continue
                }
                close(descriptor)
                releasedReserve?.replenishIfNeeded()
                if lastErr == ENOENT {
                    break
                }
                return .fallback(lastErr)
            }
        }

        return .fallback(lastErr)
    }

    private static func advisoryLockReentrancyKey(for lockURL: URL) -> String {
        "mcp-shared-lock-\(lockURL.path)"
    }

    private static func incrementAdvisoryLockReentrancy(for key: String) -> Int {
        let dictionary = Thread.current.threadDictionary
        let nextValue = (dictionary[key] as? Int ?? 0) + 1
        dictionary[key] = nextValue
        return nextValue
    }

    private static func decrementAdvisoryLockReentrancy(for key: String) {
        let dictionary = Thread.current.threadDictionary
        let currentValue = dictionary[key] as? Int ?? 0
        if currentValue <= 1 {
            dictionary.removeObject(forKey: key)
        } else {
            dictionary[key] = currentValue - 1
        }
    }

    private static func shouldUseEmergencyReserve(_ err: Int32) -> Bool {
        err == EMFILE || err == ENFILE
    }
}
