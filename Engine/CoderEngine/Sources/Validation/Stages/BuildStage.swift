import Foundation

struct BuildStage: ValidationStage {
    let id: ValidationStageID = .build

    func run(
        context: ValidationContext,
        profile: ValidationProfile,
        descriptor: ProjectValidationDescriptor
    ) async -> ValidationStageResult {
        let scheme = profile == .ciFull ? descriptor.releaseScheme : descriptor.localScheme
        do {
            let result = try await ValidationCommandExecutor.run(
                executable: "/usr/bin/xcodebuild",
                arguments: ["build", "-workspace", descriptor.workspace, "-scheme", scheme, "-destination", descriptor.destination],
                workingDirectory: context.workspaceRoot
            )
            if result.exitCode == 0 {
                return ValidationStageResult(stage: id, status: .passed, summary: "Build \(scheme) completata.", command: result.command)
            }
            return ValidationStageResult(stage: id, status: .failed, summary: "Build \(scheme) fallita.", command: result.command, logExcerpt: result.output)
        } catch {
            return ValidationStageResult(stage: id, status: .failed, summary: "Build fallita: \(error.localizedDescription)")
        }
    }
}
