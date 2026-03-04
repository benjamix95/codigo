import Foundation

// MARK: - Linting Models

/// Severità di un diagnostico di linting.
enum LintSeverity: String, Codable, Sendable {
    case error
    case warning
    case info
    case hint
}

/// Singolo diagnostico prodotto dal linter.
struct LintDiagnostic: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let filePath: String
    let line: Int
    let column: Int?
    let severity: LintSeverity
    let message: String
    let ruleId: String?
    let source: String

    init(
        filePath: String,
        line: Int,
        column: Int? = nil,
        severity: LintSeverity,
        message: String,
        ruleId: String? = nil,
        source: String = "swiftlint"
    ) {
        self.id = "\(filePath):\(line):\(column ?? 0):\(ruleId ?? ""):\(message)"
        self.filePath = filePath
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
        self.ruleId = ruleId
        self.source = source
    }
}

/// Risultato di un'operazione di linting su un file.
struct LintResult: Sendable {
    let filePath: String
    let diagnostics: [LintDiagnostic]
    let error: String?

    var isSuccess: Bool { error == nil }
    var errorCount: Int { diagnostics.filter { $0.severity == .error }.count }
    var warningCount: Int { diagnostics.filter { $0.severity == .warning }.count }

    static func success(filePath: String, diagnostics: [LintDiagnostic]) -> LintResult {
        LintResult(filePath: filePath, diagnostics: diagnostics, error: nil)
    }

    static func failure(filePath: String, error: String) -> LintResult {
        LintResult(filePath: filePath, diagnostics: [], error: error)
    }
}

/// Tipo di linter supportato.
enum LinterType: String, Sendable {
    case swiftLint = "swiftlint"
    case eslint = "eslint"
}

/// Protocollo per adapter di linting.
protocol LintingAdapter: Sendable {
    var linterType: LinterType { get }
    func lint(filePath: String) async -> LintResult
    func lintDirectory(at path: String) async -> [LintResult]
    func isAvailable() async -> Bool
}
