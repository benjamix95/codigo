import Foundation

public struct ValidationContext: Sendable {
    public let trigger: ValidationTrigger
    public let workspaceRoot: URL
    public let touchedFiles: [String]
    public let patchText: String?
    public let patchFileURL: URL?
    public let workspaceContainsPatch: Bool
    public let stagedOnly: Bool

    public init(
        trigger: ValidationTrigger,
        workspaceRoot: URL,
        touchedFiles: [String],
        patchText: String? = nil,
        patchFileURL: URL? = nil,
        workspaceContainsPatch: Bool = false,
        stagedOnly: Bool = false
    ) {
        self.trigger = trigger
        self.workspaceRoot = workspaceRoot
        self.touchedFiles = touchedFiles
        self.patchText = patchText
        self.patchFileURL = patchFileURL
        self.workspaceContainsPatch = workspaceContainsPatch
        self.stagedOnly = stagedOnly
    }
}
