import Foundation

// MARK: - LockScope

/// Scope effettivo di un lock: file + simboli (§12).
/// `lock_scope = file_scope ∪ symbol_scope`
public struct LockScope: Sendable, Equatable {
    public let files: Set<String>
    public let symbols: Set<String>

    /// Tutti gli identificatori (file + simboli) usati come chiavi lock.
    public var allKeys: Set<String> {
        files.union(symbols)
    }

    public init(files: Set<String> = [], symbols: Set<String> = []) {
        self.files = files
        self.symbols = symbols
    }

    /// Costruisce un LockScope dai campi di un TaskNode.
    public init(from task: TaskNode) {
        self.files = Set(task.fileScope)
        self.symbols = Set(task.symbolScope)
    }

    /// True se c'è sovrapposizione con un altro scope (conflitto §12).
    public func overlaps(with other: LockScope) -> Bool {
        !allKeys.isDisjoint(with: other.allKeys)
    }
}

// MARK: - PipelineLockManager

/// Wrappa `FileLockCoordinator` aggiungendo supporto per symbol scope (§12).
///
/// Responsabilità:
/// - Lock unificato file + symbol
/// - Ordinamento lessicografico per prevenzione deadlock (§5.11)
/// - Delega al FileLockCoordinator esistente
/// - Tracking proprietà lock per task
/// - Verifica ownership prima di apply
public actor PipelineLockManager {

    private let coordinator: FileLockCoordinator
    private var lockOwnership: [String: LockScope] = [:]

    public init(coordinator: FileLockCoordinator = FileLockCoordinator()) {
        self.coordinator = coordinator
    }

    // MARK: - Acquire

    /// Acquisisce lock su file_scope ∪ symbol_scope per il task.
    /// Le chiavi vengono ordinate lessicograficamente per prevenire deadlock.
    ///
    /// - Returns: `true` se il lock è stato acquisito con successo
    @discardableResult
    public func acquire(
        scope: LockScope,
        taskId: String,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) async -> Bool {
        let allKeys = scope.allKeys
        guard !allKeys.isEmpty else { return true }

        let sortedKeys = allKeys.sorted()

        let success = await coordinator.acquireLock(
            files: Set(sortedKeys),
            swarmId: taskId,
            isCancelled: isCancelled
        )

        if success {
            lockOwnership[taskId] = scope
        }

        return success
    }

    // MARK: - Release

    /// Rilascia tutti i lock di un task.
    public func release(taskId: String) async {
        guard let scope = lockOwnership[taskId] else { return }
        let allKeys = scope.allKeys
        await coordinator.releaseLock(files: allKeys, swarmId: taskId)
        lockOwnership.removeValue(forKey: taskId)
    }

    /// Rilascia tutti i lock di un task (cleanup su errore/cancellation).
    public func releaseAll(taskId: String) async {
        await coordinator.releaseAllLocks(swarmId: taskId)
        lockOwnership.removeValue(forKey: taskId)
    }

    // MARK: - Verify

    /// Verifica che il task possieda effettivamente i lock su tutti i file indicati.
    /// Usato prima di apply_transaction (§5.6 step 3).
    public func verifyOwnership(files: Set<String>, taskId: String) -> Bool {
        guard let scope = lockOwnership[taskId] else {
            return false
        }
        return files.isSubset(of: scope.allKeys)
    }

    // MARK: - Query

    /// Restituisce lo scope lock corrente per un task.
    public func scopeFor(taskId: String) -> LockScope? {
        lockOwnership[taskId]
    }

    /// Tutti i task che attualmente possiedono lock.
    public var activeLockOwners: [String] {
        Array(lockOwnership.keys)
    }

    /// Numero totale di chiavi lock attive.
    public var totalLockedKeys: Int {
        lockOwnership.values.reduce(0) { $0 + $1.allKeys.count }
    }

    // MARK: - Reset

    public func reset() async {
        for taskId in lockOwnership.keys {
            await coordinator.releaseAllLocks(swarmId: taskId)
        }
        lockOwnership.removeAll()
    }
}
