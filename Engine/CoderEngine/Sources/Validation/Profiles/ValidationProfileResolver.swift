import Foundation

public enum ValidationProfileResolver {
    public static func resolve(trigger: ValidationTrigger) -> ValidationProfile {
        switch trigger {
        case .reviewPatchPreview: .reviewPatchPreview
        case .reviewPatchApply: .reviewPatchApply
        case .gitCommit: .gitCommit
        case .ciFull: .ciFull
        }
    }
}
