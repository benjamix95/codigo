import Foundation

// MARK: - Variable Inspection Models

/// Rappresenta una variabile ispezionata dal debugger (locale, argomento, globale, registro).
struct NativeVariable: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let type: String
    let value: String
    let scope: VariableScope
    let children: [NativeVariable]

    enum VariableScope: String, Codable, Hashable, Sendable {
        case local
        case argument
        case global
        case register
    }

    init(
        name: String,
        type: String,
        value: String,
        scope: VariableScope = .local,
        children: [NativeVariable] = []
    ) {
        self.id = "\(scope.rawValue):\(name)"
        self.name = name
        self.type = type
        self.value = value
        self.scope = scope
        self.children = children
    }
}

// MARK: - Expression Evaluation

/// Risultato della valutazione di un'espressione durante la pausa del debugger.
struct ExpressionResult: Codable, Equatable, Sendable {
    let expression: String
    let result: String
    let type: String?
    let error: String?
    let success: Bool

    static func success(expression: String, result: String, type: String? = nil) -> ExpressionResult {
        ExpressionResult(expression: expression, result: result, type: type, error: nil, success: true)
    }

    static func failure(expression: String, error: String) -> ExpressionResult {
        ExpressionResult(expression: expression, result: "", type: nil, error: error, success: false)
    }
}

// MARK: - Enhanced Breakpoint Modifiers

/// Modificatori avanzati per breakpoint condizionali, hit-count, log message, one-shot.
struct BreakpointModifier: Codable, Equatable, Sendable {
    let ignoreCount: Int?
    let logMessage: String?
    let isOneShot: Bool
    let isAutoResume: Bool

    init(
        ignoreCount: Int? = nil,
        logMessage: String? = nil,
        isOneShot: Bool = false,
        isAutoResume: Bool = false
    ) {
        self.ignoreCount = ignoreCount
        self.logMessage = logMessage
        self.isOneShot = isOneShot
        self.isAutoResume = isAutoResume
    }

    static let none = BreakpointModifier()
}

// MARK: - Adapter Recovery Configuration

/// Configurazione per il meccanismo di recovery automatico dell'adapter.
struct DebugAdapterRecoveryConfiguration: Sendable {
    let maxRetries: Int
    let retryDelayNanoseconds: UInt64
    let autoRestartOnCrash: Bool

    init(
        maxRetries: Int = 3,
        retryDelayNanoseconds: UInt64 = 500_000_000,
        autoRestartOnCrash: Bool = true
    ) {
        self.maxRetries = maxRetries
        self.retryDelayNanoseconds = retryDelayNanoseconds
        self.autoRestartOnCrash = autoRestartOnCrash
    }

    static let `default` = DebugAdapterRecoveryConfiguration()
}

// MARK: - Frame Selection Result

/// Risultato della selezione di un frame nello stack trace.
struct FrameSelectionResult: Codable, Equatable, Sendable {
    let frameIndex: Int
    let function: String
    let filePath: String
    let line: Int
    let localVariables: [NativeVariable]

    static let empty = FrameSelectionResult(
        frameIndex: 0,
        function: "",
        filePath: "",
        line: 0,
        localVariables: []
    )
}
