import Foundation

struct RegressionStage: ValidationStage {
    let id: ValidationStageID = .regression

    func run(
        context: ValidationContext,
        profile: ValidationProfile,
        descriptor: ProjectValidationDescriptor
    ) async -> ValidationStageResult {
        guard profile == .gitCommit || profile == .ciFull || profile == .reviewPatchApply else {
            return ValidationStageResult(stage: id, status: .skipped, summary: "Regression gate non richiesto dal profilo.")
        }
        let result = CodeReviewAuditService.runTool(
            named: ReviewAuditToolName.bugTestImpact,
            scopeFiles: context.touchedFiles,
            workspacePath: context.workspaceRoot
        )
        let blocking = result.findings.filter { $0.blocking || $0.severity == .critical }
        if !blocking.isEmpty {
            return ValidationStageResult(
                stage: id,
                status: .failed,
                summary: "Regression risk bloccante rilevato.",
                logExcerpt: blocking.prefix(3).map(\.message).joined(separator: " | ")
            )
        }
        return ValidationStageResult(stage: id, status: .passed, summary: result.summary)
    }
}
