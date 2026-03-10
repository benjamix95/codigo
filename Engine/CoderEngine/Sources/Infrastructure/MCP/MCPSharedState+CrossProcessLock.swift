import Darwin
import Foundation

extension MCPSharedState {
    enum AdvisoryFileLockAcquisition {
        case locked(Int32)
        case fallback(Int32)
    }

    private struct NamedSemaphoreHandle {
        let name: String
        let semaphore: UnsafeMutablePointer<sem_t>
    }

    private static let codeReviewFallbackLock = NSRecursiveLock()
    private static let bugHunterFallbackLock = NSRecursiveLock()

    static func withCodeReviewFileLock<T>(
        _ body: () -> T
    ) -> T {
        withAdvisoryFileLock(
            label: "CodeReviewLock",
            lockURL: codeReviewDirectoryPath.appendingPathComponent(".lock"),
            createMode: S_IRUSR | S_IWUSR,
            fallbackLock: codeReviewFallbackLock,
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

        return withCrossProcessSemaphore(
            label: label,
            lockURL: lockURL,
            createMode: createMode
        ) {
            let acquisition = acquireLock?() ?? acquireAdvisoryFileLock(
                lockURL: lockURL,
                createMode: createMode,
                ensureLockDirectory: ensureLockDirectory
            )

            switch acquisition {
            case .locked(let descriptor):
                defer { close(descriptor) }
                defer { flock(descriptor, LOCK_UN) }
                return body()
            case .fallback(let err):
                print(
                    "[MCPSharedState] ⚠️ \(label): fallback al solo gate cross-process per \(lockURL.path), errno: \(err)"
                )
                ensureLockDirectory()
                return body()
            }
        }
    }

    static func acquireAdvisoryFileLock(
        lockURL: URL,
        createMode: mode_t,
        ensureLockDirectory: () -> Void
    ) -> AdvisoryFileLockAcquisition {
        var lastErr: Int32 = 0

        for _ in 0..<2 {
            ensureLockDirectory()
            let descriptor = open(lockURL.path, O_CREAT | O_RDWR, createMode)
            guard descriptor >= 0 else {
                lastErr = errno
                if lastErr == ENOENT {
                    continue
                }
                return .fallback(lastErr)
            }

            while true {
                let lockResult = flock(descriptor, LOCK_EX)
                if lockResult == 0 {
                    return .locked(descriptor)
                }

                lastErr = errno
                if lastErr == EINTR {
                    continue
                }
                close(descriptor)
                if lastErr == ENOENT {
                    break
                }
                return .fallback(lastErr)
            }
        }

        return .fallback(lastErr)
    }

    private static func withCrossProcessSemaphore<T>(
        label: String,
        lockURL: URL,
        createMode: mode_t,
        body: () -> T
    ) -> T {
        let handle = openCrossProcessSemaphore(
            label: label,
            lockURL: lockURL,
            createMode: createMode
        )
        defer {
            if sem_post(handle.semaphore) != 0 {
                let err = errno
                print(
                    "[MCPSharedState] ⚠️ \(label): sem_post fallito su \(handle.name), errno: \(err)"
                )
            }
            sem_close(handle.semaphore)
        }

        while sem_wait(handle.semaphore) == -1 {
            let err = errno
            if err == EINTR {
                continue
            }
            fatalError(
                "\(label): impossibile acquisire il semaforo cross-process \(handle.name), errno: \(err)"
            )
        }

        return body()
    }

    private static func openCrossProcessSemaphore(
        label: String,
        lockURL: URL,
        createMode: mode_t
    ) -> NamedSemaphoreHandle {
        let name = crossProcessSemaphoreName(for: lockURL)
        guard let semaphore = sem_open(name, O_CREAT, createMode, 1),
              semaphore != SEM_FAILED else {
            let err = errno
            fatalError(
                "\(label): impossibile aprire il semaforo cross-process \(name), errno: \(err)"
            )
        }
        return NamedSemaphoreHandle(name: name, semaphore: semaphore)
    }

    private static func advisoryLockReentrancyKey(for lockURL: URL) -> String {
        "mcp-shared-lock-\(crossProcessSemaphoreName(for: lockURL))"
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

    private static func crossProcessSemaphoreName(for lockURL: URL) -> String {
        "/solocode-\(String(fnv1a64(lockURL.path), radix: 16))"
    }

    private static func fnv1a64(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
