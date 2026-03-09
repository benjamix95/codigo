import Foundation

struct TargetedTestsStage: ValidationStage {
    let id: ValidationStageID = .targetedTests

    func run(
        context: ValidationContext,
        profile: ValidationProfile,
        descriptor: ProjectValidationDescriptor
    ) async -> ValidationStageResult {
        let groups = TargetedTestsSelector.select(files: context.touchedFiles, descriptor: descriptor)
        guard !groups.isEmpty else {
            return ValidationStageResult(stage: id, status: .skipped, summary: "Nessun gruppo test selezionato.")
        }

        for group in groups {
            do {
                let args = [
                    "test", "-workspace", descriptor.workspace,
                    "-scheme", descriptor.localScheme,
                    "-destination", descriptor.destination,
                ] + group.onlyTesting.flatMap { ["-only-testing:\($0)"] }
                let result = try await ValidationCommandExecutor.run(
                    executable: "/usr/bin/xcodebuild",
                    arguments: args,
                    workingDirectory: context.workspaceRoot
                )
                if result.exitCode != 0 {
                    return ValidationStageResult(
                        stage: id,
                        status: .failed,
                        summary: "Test mirati falliti per \(group.id).",
                        command: result.command,
                        logExcerpt: result.output
                    )
                }
            } catch {
                return ValidationStageResult(stage: id, status: .failed, summary: "Test mirati falliti: \(error.localizedDescription)")
            }
        }

        return ValidationStageResult(
            stage: id,
            status: .passed,
            summary: "Test mirati superati per \(groups.map(\.id).joined(separator: ", "))."
        )
    }
}
