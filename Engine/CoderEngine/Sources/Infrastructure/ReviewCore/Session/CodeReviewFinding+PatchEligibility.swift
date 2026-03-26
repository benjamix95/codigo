import Foundation

extension CodeReviewFinding {
    /// `true` only after Rust-backed deep verification succeeded (real bug, not inconclusive / FP).
    public var isBugConfirmedForPatchPreparation: Bool {
        guard verifiedAt != nil else { return false }
        let trimmed = verificationReport?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.count >= 8 else { return false }
        if let method = verificationMethod?.lowercased(), method.contains("rust_core_unavailable") {
            return false
        }
        if let fp = falsePositiveReason?.trimmingCharacters(in: .whitespacesAndNewlines), !fp.isEmpty {
            return false
        }
        return true
    }
}

extension ReviewPatchArtifact {
    /// User may apply only after prepare produced a verified patch **and** a visible diff.
    public var isReadyForUserApply: Bool {
        let diff = diffPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !diff.isEmpty else { return false }
        return verifyStatus == .verified
    }
}
