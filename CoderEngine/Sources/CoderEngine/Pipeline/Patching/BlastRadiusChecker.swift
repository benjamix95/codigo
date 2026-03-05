import Foundation

// MARK: - BlastRadiusResult

/// Risultato del blast radius check su un set di patch (§13.3).
public struct BlastRadiusResult: Sendable, Equatable {
    public let totalUniqueFiles: Int
    public let level: BlastRadiusLevel
    public let requiresExtraReview: Bool
    public let requiresManualApproval: Bool

    public init(
        totalUniqueFiles: Int,
        level: BlastRadiusLevel,
        requiresExtraReview: Bool,
        requiresManualApproval: Bool
    ) {
        self.totalUniqueFiles = totalUniqueFiles
        self.level = level
        self.requiresExtraReview = requiresExtraReview
        self.requiresManualApproval = requiresManualApproval
    }
}

// MARK: - BlastRadiusChecker

/// Verifica il blast radius di un patch set (§13.3).
///
/// Soglie:
/// - `> 12` file: review extra obbligatoria
/// - `> 25` file: approval manuale obbligatoria
public struct BlastRadiusChecker: Sendable {

    public static let extraReviewThreshold = 12
    public static let manualApprovalThreshold = 25

    public init() {}

    /// Esegue il blast radius check su un set di patch.
    public func check(patches: [PatchManifest]) -> BlastRadiusResult {
        let uniqueFiles = countUniqueFiles(patches: patches)
        let level = classifyLevel(fileCount: uniqueFiles)

        return BlastRadiusResult(
            totalUniqueFiles: uniqueFiles,
            level: level,
            requiresExtraReview: level == .extraReview || level == .manualApproval,
            requiresManualApproval: level == .manualApproval
        )
    }

    /// Check su una singola patch.
    public func check(patch: PatchManifest) -> BlastRadiusResult {
        check(patches: [patch])
    }

    /// Check su un elenco esplicito di file.
    public func check(files: [String]) -> BlastRadiusResult {
        let uniqueCount = Set(files).count
        let level = classifyLevel(fileCount: uniqueCount)

        return BlastRadiusResult(
            totalUniqueFiles: uniqueCount,
            level: level,
            requiresExtraReview: level == .extraReview || level == .manualApproval,
            requiresManualApproval: level == .manualApproval
        )
    }

    /// Conta i file unici toccati dall'intero patch set.
    public func countUniqueFiles(patches: [PatchManifest]) -> Int {
        var allFiles = Set<String>()
        for patch in patches {
            allFiles.formUnion(patch.touchedFiles)
        }
        return allFiles.count
    }

    /// Classifica il livello di blast radius dato il conteggio file.
    public func classifyLevel(fileCount: Int) -> BlastRadiusLevel {
        if fileCount > Self.manualApprovalThreshold { return .manualApproval }
        if fileCount > Self.extraReviewThreshold { return .extraReview }
        return .normal
    }

    /// Ritorna `true` se il patch set può procedere senza blocchi.
    /// Un patch set con `manualApproval` richiede gate esplicito.
    public func canProceedWithoutGate(patches: [PatchManifest]) -> Bool {
        check(patches: patches).level == .normal
    }
}
