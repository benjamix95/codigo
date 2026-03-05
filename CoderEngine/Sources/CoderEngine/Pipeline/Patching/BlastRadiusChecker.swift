import Foundation

// MARK: - BlastRadiusResult

/// Risultato del blast radius check (§13.3).
public enum BlastRadiusResult: Sendable, Equatable {
    /// Entro soglia: ≤12 file unici.
    case normal(fileCount: Int)
    /// Review extra obbligatoria: 13..25 file.
    case extraReviewRequired(fileCount: Int)
    /// Approvazione manuale obbligatoria: >25 file.
    case manualApprovalRequired(fileCount: Int)

    public var fileCount: Int {
        switch self {
        case .normal(let c), .extraReviewRequired(let c),
             .manualApprovalRequired(let c):
            return c
        }
    }

    public var isBlocked: Bool {
        if case .manualApprovalRequired = self { return true }
        return false
    }

    public var needsExtraReview: Bool {
        switch self {
        case .extraReviewRequired, .manualApprovalRequired: return true
        case .normal: return false
        }
    }
}

// MARK: - BlastRadiusThresholds

/// Soglie configurabili per il blast radius check.
public struct BlastRadiusThresholds: Sendable, Equatable {
    public let extraReviewThreshold: Int
    public let manualApprovalThreshold: Int

    public static let `default` = BlastRadiusThresholds(
        extraReviewThreshold: 12,
        manualApprovalThreshold: 25
    )

    public init(extraReviewThreshold: Int, manualApprovalThreshold: Int) {
        self.extraReviewThreshold = extraReviewThreshold
        self.manualApprovalThreshold = manualApprovalThreshold
    }
}

// MARK: - BlastRadiusChecker

/// Verifica il blast radius di un patch-set (§13.3).
///
/// Regole:
/// - patch > 12 file unici → review extra obbligatoria
/// - patch > 25 file unici → approval manuale obbligatoria
public struct BlastRadiusChecker: Sendable {

    public let thresholds: BlastRadiusThresholds

    public init(thresholds: BlastRadiusThresholds = .default) {
        self.thresholds = thresholds
    }

    /// Controlla il blast radius per un singolo PatchManifest.
    public func check(patch: PatchManifest) -> BlastRadiusResult {
        checkFileCount(patch.touchedFiles.count)
    }

    /// Controlla il blast radius per un patch-set (più manifest).
    /// I file unici vengono contati una volta sola anche se toccati
    /// da più patch.
    public func check(patchSet: [PatchManifest]) -> BlastRadiusResult {
        let uniqueFiles = Set(patchSet.flatMap(\.touchedFiles))
        return checkFileCount(uniqueFiles.count)
    }

    /// Controlla dato un conteggio esplicito di file.
    public func checkFileCount(_ count: Int) -> BlastRadiusResult {
        if count > thresholds.manualApprovalThreshold {
            return .manualApprovalRequired(fileCount: count)
        } else if count > thresholds.extraReviewThreshold {
            return .extraReviewRequired(fileCount: count)
        } else {
            return .normal(fileCount: count)
        }
    }

    /// Estrae la lista di file unici da un patch-set.
    public func uniqueFiles(from patchSet: [PatchManifest]) -> Set<String> {
        Set(patchSet.flatMap(\.touchedFiles))
    }

    /// Conta i file unici in un patch-set.
    public func uniqueFileCount(from patchSet: [PatchManifest]) -> Int {
        uniqueFiles(from: patchSet).count
    }
}
