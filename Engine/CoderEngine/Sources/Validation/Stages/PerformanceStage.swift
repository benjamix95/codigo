import Foundation

struct PerformanceStage: ValidationStage {
    let id: ValidationStageID = .performance

    func run(
        context: ValidationContext,
        profile: ValidationProfile,
        descriptor: ProjectValidationDescriptor
    ) async -> ValidationStageResult {
        guard profile == .ciFull else {
            return ValidationStageResult(stage: id, status: .skipped, summary: "Performance gate riservato a ciFull.")
        }
        do {
            let result = try await ValidationCommandExecutor.run(
                executable: "/usr/bin/xcodebuild",
                arguments: [
                    "test", "-workspace", descriptor.workspace,
                    "-scheme", descriptor.localScheme,
                    "-destination", descriptor.destination,
                    "-only-testing:CoderEngineTests/ValidationPerformanceTests",
                ],
                workingDirectory: context.workspaceRoot
            )
            let status: ValidationStageStatus = result.exitCode == 0 ? .passed : .failed
            return ValidationStageResult(stage: id, status: status, summary: "Performance suite \(status.rawValue).", command: result.command, logExcerpt: status == .failed ? result.output : nil)
        } catch {
            return ValidationStageResult(stage: id, status: .failed, summary: "Performance suite fallita: \(error.localizedDescription)")
        }
    }
}
