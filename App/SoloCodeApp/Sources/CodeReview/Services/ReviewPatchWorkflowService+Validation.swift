import CoderEngine
import Foundation

extension ReviewPatchWorkflowService {
    func validatePreparedArtifact(
        _ artifact: ReviewPatchArtifact,
        workspaceRoot: String,
        trigger: ValidationTrigger,
        workspaceContainsPatch: Bool
    ) async throws -> ReviewPatchArtifact {
        let validation = try await runValidation(
            trigger: trigger,
            workspaceRoot: workspaceRoot,
            touchedFiles: artifact.touchedFiles,
            patchText: artifact.patchText,
            workspaceContainsPatch: workspaceContainsPatch
        )
        guard validation.status == .passed else {
            throw ReviewPatchWorkflowError.validationFailed(validation.summaryLine)
        }
        var validated = artifact
        validated.status = .verified
        validated.verifyStatus = .verified
        validated.validationRunId = validation.runId
        validated.validationStatus = validation.status
        validated.validationSummary = ValidationReportFormatter.summary(for: validation)
        validated.updatedAt = Date()
        return validated
    }

    func runValidation(
        trigger: ValidationTrigger,
        workspaceRoot: String,
        touchedFiles: [String],
        patchText: String?,
        workspaceContainsPatch: Bool
    ) async throws -> ValidationRunResult {
        let patchFileURL: URL?
        if let patchText, !patchText.isEmpty {
            patchFileURL = try writePatchTempFile(patchText, prefix: trigger.rawValue)
        } else {
            patchFileURL = nil
        }
        defer {
            if let patchFileURL {
                try? FileManager.default.removeItem(at: patchFileURL)
            }
        }

        let context = ValidationContext(
            trigger: trigger,
            workspaceRoot: URL(fileURLWithPath: workspaceRoot),
            touchedFiles: touchedFiles,
            patchText: patchText,
            patchFileURL: patchFileURL,
            workspaceContainsPatch: workspaceContainsPatch,
            stagedOnly: trigger == .gitCommit
        )
        return try await ValidationOrchestrator().run(context: context)
    }
}
