import CoderEngine
import Foundation

struct ReviewPatchApplyExecutionContext {
    let patchFilePrefix: String
    let validationTrigger: String
    let workspaceContainsPatch: Bool
}

struct ReviewPatchRevalidateExecutionContext {
    let validationTrigger: String
    let workspaceContainsPatch: Bool
}

struct ReviewPatchRollbackExecutionContext {
    let patchFilePrefix: String
}

