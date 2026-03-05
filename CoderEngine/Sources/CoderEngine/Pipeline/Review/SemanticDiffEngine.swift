import Foundation

// MARK: - SemanticChange

/// Singolo cambio semantico rilevato dall'AST diff (§8.6).
public struct SemanticChange: Codable, Sendable, Equatable {
    public var type: SemanticChangeType
    public var symbol: String?
    public var file: String
    public var before: String?
    public var after: String?
    public var summary: String?
    public var impact: SemanticImpact
    public var module: String?

    public init(
        type: SemanticChangeType,
        symbol: String? = nil,
        file: String,
        before: String? = nil,
        after: String? = nil,
        summary: String? = nil,
        impact: SemanticImpact,
        module: String? = nil
    ) {
        self.type = type
        self.symbol = symbol
        self.file = file
        self.before = before
        self.after = after
        self.summary = summary
        self.impact = impact
        self.module = module
    }
}

// MARK: - SemanticDiffSummary

/// Summary aggregato dei cambi semantici (§8.6).
public struct SemanticDiffSummary: Codable, Sendable, Equatable {
    public var breakingChanges: Int
    public var behaviorChanges: Int
    public var dependencyChanges: Int
    public var cosmeticChanges: Int
    public var totalSemanticChanges: Int

    public init(
        breakingChanges: Int = 0,
        behaviorChanges: Int = 0,
        dependencyChanges: Int = 0,
        cosmeticChanges: Int = 0,
        totalSemanticChanges: Int = 0
    ) {
        self.breakingChanges = breakingChanges
        self.behaviorChanges = behaviorChanges
        self.dependencyChanges = dependencyChanges
        self.cosmeticChanges = cosmeticChanges
        self.totalSemanticChanges = totalSemanticChanges
    }

    enum CodingKeys: String, CodingKey {
        case breakingChanges = "breaking_changes"
        case behaviorChanges = "behavior_changes"
        case dependencyChanges = "dependency_changes"
        case cosmeticChanges = "cosmetic_changes"
        case totalSemanticChanges = "total_semantic_changes"
    }
}

// MARK: - SemanticDiffReport

/// Report completo del semantic diff (§8.6).
public struct SemanticDiffReport: Codable, Sendable, Equatable {
    public var semanticDiffId: String
    public var taskId: String
    public var patchId: String
    public var changes: [SemanticChange]
    public var summary: SemanticDiffSummary

    public init(
        semanticDiffId: String,
        taskId: String,
        patchId: String,
        changes: [SemanticChange],
        summary: SemanticDiffSummary? = nil
    ) {
        self.semanticDiffId = semanticDiffId
        self.taskId = taskId
        self.patchId = patchId
        self.changes = changes
        self.summary = summary ?? Self.computeSummary(from: changes)
    }

    enum CodingKeys: String, CodingKey {
        case semanticDiffId = "semantic_diff_id"
        case taskId = "task_id"
        case patchId = "patch_id"
        case changes
        case summary
    }

    /// Filtra i cambi non cosmetici per ridurre rumore nella review.
    public var nonCosmeticChanges: [SemanticChange] {
        changes.filter { $0.impact != .cosmetic }
    }

    /// `true` se almeno un cambio è breaking (§8.6 vincolo 3).
    public var hasBreakingChanges: Bool {
        changes.contains { $0.impact == .breakingChange }
    }

    static func computeSummary(
        from changes: [SemanticChange]
    ) -> SemanticDiffSummary {
        var s = SemanticDiffSummary()
        for change in changes {
            switch change.impact {
            case .breakingChange: s.breakingChanges += 1
            case .behaviorChange: s.behaviorChanges += 1
            case .dependencyChange: s.dependencyChanges += 1
            case .cosmetic: s.cosmeticChanges += 1
            }
        }
        s.totalSemanticChanges = changes.count
        return s
    }
}

// MARK: - SemanticDiffEngine

/// Motore di semantic diff pre-review basato su AST (§8.6).
///
/// Vincoli dalla spec:
/// - MUST essere generato PRIMA del dispatch dei reviewer
/// - MUST essere incluso nel contesto dei reviewer
/// - `breaking_change` MUST generare finding `critical` automatico
/// - `cosmetic_only` SHOULD essere escluso dalla review
/// - MUST essere allegato al `patch_manifest.json` come `semantic_diff_path`
public struct SemanticDiffEngine: Sendable {

    public init() {}

    // MARK: - Generate Diff

    /// Genera un semantic diff report a partire dalla lista di cambi rilevati.
    public func generateReport(
        taskId: String,
        patchId: String,
        changes: [SemanticChange]
    ) -> SemanticDiffReport {
        let diffId = "sdiff_\(patchId.prefix(8))"
        return SemanticDiffReport(
            semanticDiffId: diffId,
            taskId: taskId,
            patchId: patchId,
            changes: changes
        )
    }

    // MARK: - Analysis Helpers

    /// Classifica automaticamente l'impatto di un cambio di signature.
    public func classifySignatureChange(
        symbol: String,
        file: String,
        oldSignature: String,
        newSignature: String,
        isPublic: Bool
    ) -> SemanticChange {
        let impact: SemanticImpact = isPublic
            ? .breakingChange : .behaviorChange
        return SemanticChange(
            type: .functionSignatureChanged,
            symbol: symbol,
            file: file,
            before: oldSignature,
            after: newSignature,
            impact: impact
        )
    }

    /// Classifica un cambio di import.
    public func classifyImportChange(
        file: String,
        module: String,
        added: Bool
    ) -> SemanticChange {
        SemanticChange(
            type: added ? .importAdded : .importRemoved,
            file: file,
            impact: .dependencyChange,
            module: module
        )
    }

    /// Filtra cambi cosmetici dal report per ridurre rumore (§8.6 vincolo 4).
    public func filterCosmeticChanges(
        from report: SemanticDiffReport
    ) -> SemanticDiffReport {
        let filtered = report.nonCosmeticChanges
        return SemanticDiffReport(
            semanticDiffId: report.semanticDiffId,
            taskId: report.taskId,
            patchId: report.patchId,
            changes: filtered
        )
    }

    /// Estrae i breaking changes che richiedono finding `critical` automatico.
    public func extractBreakingChanges(
        from report: SemanticDiffReport
    ) -> [SemanticChange] {
        report.changes.filter { $0.impact == .breakingChange }
    }
}
