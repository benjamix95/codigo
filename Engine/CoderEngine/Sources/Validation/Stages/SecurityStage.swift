import Foundation

struct SecurityStage: ValidationStage {
    let id: ValidationStageID = .security

    func run(
        context: ValidationContext,
        profile: ValidationProfile,
        descriptor: ProjectValidationDescriptor
    ) async -> ValidationStageResult {
        guard context.touchedFiles.contains(where: descriptor.isSecuritySensitive(path:)) || profile == .ciFull else {
            return ValidationStageResult(stage: id, status: .skipped, summary: "Nessun path sensibile: security gate saltato.")
        }

        let tools = [
            ReviewAuditToolName.securityPatterns,
            ReviewAuditToolName.securitySecrets,
        ]
        let findings = tools.flatMap {
            CodeReviewAuditService.runTool(
                named: $0,
                scopeFiles: context.touchedFiles,
                workspacePath: context.workspaceRoot
            ).findings
        }
        let blocking = findings.filter { $0.blocking || $0.severity == .critical }
        if !blocking.isEmpty {
            return ValidationStageResult(
                stage: id,
                status: .failed,
                summary: "Security findings bloccanti: \(blocking.count).",
                logExcerpt: blocking.prefix(3).map(\.message).joined(separator: " | ")
            )
        }
        return ValidationStageResult(stage: id, status: .passed, summary: "Security suite completata senza finding bloccanti.")
    }
}
