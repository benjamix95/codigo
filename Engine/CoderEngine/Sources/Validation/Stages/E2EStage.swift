import Foundation

struct E2EStage: ValidationStage {
    let id: ValidationStageID = .e2e

    func run(
        context: ValidationContext,
        profile: ValidationProfile,
        descriptor: ProjectValidationDescriptor
    ) async -> ValidationStageResult {
        guard profile == .ciFull else {
            return ValidationStageResult(stage: id, status: .skipped, summary: "E2E gate riservato a ciFull.")
        }
        let testsDir = context.workspaceRoot.appendingPathComponent("Tests/SoloCodeIntegrationTests")
        let hasIntegrationTests = (try? FileManager.default.contentsOfDirectory(atPath: testsDir.path))
            .map { entries in entries.contains { $0.hasSuffix(".swift") } } ?? false
        guard hasIntegrationTests else {
            return ValidationStageResult(stage: id, status: .skipped, summary: "SoloCodeIntegrationTests non popolato: E2E saltato.")
        }
        do {
            let result = try await ValidationCommandExecutor.run(
                executable: "/usr/bin/xcodebuild",
                arguments: [
                    "test", "-workspace", descriptor.workspace,
                    "-scheme", descriptor.localScheme,
                    "-destination", descriptor.destination,
                    "-only-testing:SoloCodeIntegrationTests",
                ],
                workingDirectory: context.workspaceRoot
            )
            let status: ValidationStageStatus = result.exitCode == 0 ? .passed : .failed
            return ValidationStageResult(stage: id, status: status, summary: "E2E suite \(status.rawValue).", command: result.command, logExcerpt: status == .failed ? result.output : nil)
        } catch {
            return ValidationStageResult(stage: id, status: .failed, summary: "E2E suite fallita: \(error.localizedDescription)")
        }
    }
}
