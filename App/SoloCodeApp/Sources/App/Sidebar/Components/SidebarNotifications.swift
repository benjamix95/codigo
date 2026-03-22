import Foundation

extension Notification.Name {
    /// Sidebar requests adding a folder to an existing context.
    /// UserInfo: ["contextId": UUID]
    static let sidebarAddFolderToContext = Notification.Name("CoderIDE.Sidebar.AddFolderToContext")
}
