import Foundation

/// Esegue l’intera suite di test dello scheme Xcode (tutti i target di test inclusi nello scheme).
/// Usata dopo patch/apply e pre-commit per intercettare regressioni fuori dai soli file toccati.
struct FullSchemeTestsStage: ValidationStage {
    let id: ValidationStageID = .fullSchemeTests

    func run(
        context: ValidationContext,
        profile: ValidationProfile,
        descriptor: ProjectValidationDescriptor
    ) async -> ValidationStageResult {
        guard profile == .reviewPatchApply || profile == .gitCommit else {
            return ValidationStageResult(
                stage: id,
                status: .skipped,
                summary: "Suite completa non richiesta da questo profilo di validazione."
            )
        }

        let scheme = descriptor.localScheme
        do {
            var arguments = [
                "test",
                "-workspace", descriptor.workspace,
                "-scheme", scheme,
                "-destination", descriptor.destination,
            ]
            if let plan = descriptor.testPlan, !plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                arguments.append(contentsOf: ["-testPlan", plan])
            }

            let result = try await ValidationCommandExecutor.run(
                executable: "/usr/bin/xcodebuild",
                arguments: arguments,
                workingDirectory: context.workspaceRoot
            )
            if result.exitCode == 0 {
                return ValidationStageResult(
                    stage: id,
                    status: .passed,
                    summary: "Suite test completa (\(scheme)) superata.",
                    command: result.command
                )
            }
            return ValidationStageResult(
                stage: id,
                status: .failed,
                summary: "Suite test completa (\(scheme)) fallita: correggere tutti i test rossi (anche non direttamente collegati al file del finding) e ripetere.",
                command: result.command,
                logExcerpt: result.output
            )
        } catch {
            return ValidationStageResult(
                stage: id,
                status: .failed,
                summary: "Suite test completa fallita: \(error.localizedDescription)"
            )
        }
    }
}
