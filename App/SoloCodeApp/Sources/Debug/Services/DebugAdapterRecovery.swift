import Foundation

// MARK: - Debug Adapter Crash Recovery

/// Gestisce il recovery automatico del debug adapter dopo crash o errori.
/// Wrappa un NativeDebugAdapter e fornisce auto-restart con backoff esponenziale.
actor DebugAdapterRecovery {
    private let configuration: DebugAdapterRecoveryConfiguration
    private var adapterFactory: () -> NativeDebugAdapter
    private var currentAdapter: NativeDebugAdapter
    private var consecutiveFailures: Int = 0
    private var totalRecoveryAttempts: Int = 0
    private var lastRecoveryAttempt: Date?
    private var isRecovering: Bool = false

    init(
        adapter: NativeDebugAdapter,
        adapterFactory: @escaping () -> NativeDebugAdapter,
        configuration: DebugAdapterRecoveryConfiguration = .default
    ) {
        self.currentAdapter = adapter
        self.adapterFactory = adapterFactory
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Esegue un'operazione sull'adapter con recovery automatico.
    /// Se l'adapter crasha, tenta il restart e ripete l'operazione.
    func execute<T>(
        _ operation: @escaping (NativeDebugAdapter) async -> T,
        isRecoverable: @escaping (T) -> Bool
    ) async -> T {
        let result = await operation(currentAdapter)

        if isRecoverable(result) {
            consecutiveFailures = 0
            return result
        }

        guard configuration.autoRestartOnCrash else {
            return result
        }

        return await attemptRecovery(operation: operation, isRecoverable: isRecoverable)
    }

    /// Esegue un'operazione che restituisce NativeDebugSessionState con recovery.
    func executeSessionOp(
        _ operation: @escaping (NativeDebugAdapter) async -> NativeDebugSessionState
    ) async -> NativeDebugSessionState {
        await execute(operation) { state in
            state.status != .error
        }
    }

    /// Restituisce lo stato corrente del recovery.
    func recoveryStatus() -> RecoveryStatus {
        RecoveryStatus(
            consecutiveFailures: consecutiveFailures,
            totalRecoveryAttempts: totalRecoveryAttempts,
            isRecovering: isRecovering,
            lastRecoveryAttempt: lastRecoveryAttempt,
            maxRetries: configuration.maxRetries
        )
    }

    /// Reset manuale del contatore fallimenti.
    func resetFailureCount() {
        consecutiveFailures = 0
    }

    // MARK: - Recovery Logic

    private func attemptRecovery<T>(
        operation: @escaping (NativeDebugAdapter) async -> T,
        isRecoverable: @escaping (T) -> Bool
    ) async -> T {
        guard !isRecovering else {
            return await operation(currentAdapter)
        }

        isRecovering = true
        defer { isRecovering = false }

        for attempt in 1...configuration.maxRetries {
            consecutiveFailures += 1
            totalRecoveryAttempts += 1
            lastRecoveryAttempt = Date()

            // Backoff esponenziale tra tentativi
            let delay = configuration.retryDelayNanoseconds * UInt64(attempt)
            try? await Task.sleep(nanoseconds: delay)

            // Crea nuovo adapter
            let newAdapter = adapterFactory()
            currentAdapter = newAdapter

            let result = await operation(newAdapter)
            if isRecoverable(result) {
                consecutiveFailures = 0
                return result
            }
        }

        // Tutti i tentativi falliti — restituisci ultimo risultato
        return await operation(currentAdapter)
    }
}

// MARK: - Recovery Status Model

struct RecoveryStatus: Sendable {
    let consecutiveFailures: Int
    let totalRecoveryAttempts: Int
    let isRecovering: Bool
    let lastRecoveryAttempt: Date?
    let maxRetries: Int

    var isHealthy: Bool {
        consecutiveFailures == 0
    }

    var hasExhaustedRetries: Bool {
        consecutiveFailures >= maxRetries
    }
}

// MARK: - Convenience Factory

extension DebugAdapterRecovery {
    /// Crea un recovery wrapper per il default LLDB adapter.
    static func forLLDB(
        configuration: DebugAdapterRecoveryConfiguration = .default
    ) -> DebugAdapterRecovery {
        let factory: () -> NativeDebugAdapter = {
            LLDBDAPDebugAdapter()
        }
        return DebugAdapterRecovery(
            adapter: factory(),
            adapterFactory: factory,
            configuration: configuration
        )
    }
}
