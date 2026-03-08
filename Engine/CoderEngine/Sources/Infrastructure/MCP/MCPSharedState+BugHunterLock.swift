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

        // O_CREAT | O_RDWR: crea atomicamente il file se non esiste,
        // eliminando il race TOCTOU di fileExists + createFile.
        let descriptor = open(lockPath, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else {
            // Se open fallisce nonostante O_CREAT (disco pieno, permessi),
            // NON eseguire senza lock — crash deterministico per evitare
            // corruzioni dati da operazioni concorrenti senza protezione.
            let err = errno
            fatalError(
                "BugHunterLock: impossibile aprire il file di lock: \(lockPath), errno: \(err)"
            )
        }
        defer { close(descriptor) }

        let lockResult = flock(descriptor, LOCK_EX)
        guard lockResult == 0 else {
            let err = errno
            close(descriptor)
            fatalError(
                "BugHunterLock: flock LOCK_EX fallito su \(lockPath), errno: \(err)"
            )
        }
        defer { flock(descriptor, LOCK_UN) }
        return operation()
    }
}
