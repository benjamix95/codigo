import CoderEngine
import Foundation

extension GitService {
    func validateForCommit(
        gitRoot: String,
        stagedFiles: [String]
    ) async throws -> ValidationRunResult {
        let context = ValidationContext(
            trigger: .gitCommit,
            workspaceRoot: URL(fileURLWithPath: gitRoot),
            touchedFiles: stagedFiles,
            patchText: nil,
            patchFileURL: nil,
            workspaceContainsPatch: false,
            stagedOnly: true
        )
        return try await ValidationOrchestrator().run(context: context)
    }
}
