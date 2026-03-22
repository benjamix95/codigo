import Foundation

/// Which folder picker action is pending.
enum FolderPickerKind: Equatable {
    case none
    /// Open a new project (multi-select).
    case openProject
    /// Add a folder to an existing context (single-select).
    case addFolderToContext(UUID)
}
