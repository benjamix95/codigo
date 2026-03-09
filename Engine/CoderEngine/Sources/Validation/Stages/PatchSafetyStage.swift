import Foundation

struct PatchSafetyStage: ValidationStage {
    let id: ValidationStageID = .patchSafety

    func run(
        context: ValidationContext,
        profile: ValidationProfile,
        descriptor: ProjectValidationDescriptor
    ) async -> ValidationStageResult {
        let files = ChangeScopeAnalyzer.normalize(context.touchedFiles)
        let illegal = files.first { $0.hasPrefix("/") || $0.contains("..") || $0.contains(".git/") }
        if let illegal {
            return ValidationStageResult(
                stage: id,
                status: .failed,
                summary: "Patch fuori scope o con path non sicuro: \(illegal)"
            )
        }
        if context.workspaceContainsPatch {
            return ValidationStageResult(
                stage: id,
                status: .passed,
                summary: "Workspace già mutato: controllo path e blast locale superato."
            )
        }
        guard let patchFileURL = context.patchFileURL else {
            return ValidationStageResult(
                stage: id,
                status: .skipped,
                summary: "Nessun patch file disponibile per git apply --check."
            )
        }
        do {
            let result = try await ValidationCommandExecutor.run(
                executable: "/usr/bin/git",
                arguments: ["apply", "--check", patchFileURL.path],
                workingDirectory: context.workspaceRoot
            )
            if result.exitCode == 0 {
                return ValidationStageResult(stage: id, status: .passed, summary: "git apply --check superato.", command: result.command)
            }
            return ValidationStageResult(stage: id, status: .failed, summary: "git apply --check fallito.", command: result.command, logExcerpt: result.output)
        } catch {
            return ValidationStageResult(stage: id, status: .failed, summary: "git apply --check fallito: \(error.localizedDescription)")
        }
    }
}
