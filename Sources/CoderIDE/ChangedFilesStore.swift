import SwiftUI

@MainActor
final class ChangedFilesStore: ObservableObject {
    @Published private(set) var files: [GitChangedFile] = []
    @Published private(set) var totalAdded: Int = 0
    @Published private(set) var totalRemoved: Int = 0
    @Published var isVisiblePanel: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var error: String?
    @Published private(set) var gitRoot: String?

    private let gitService = GitService()

    func refresh(workingDirectory: String?) {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let root = try gitService.resolveGitRoot(from: workingDirectory)
            gitRoot = root
            let changed = try gitService.changedFiles(gitRoot: root)
            files = changed
            totalAdded = changed.reduce(0) { $0 + $1.added }
            totalRemoved = changed.reduce(0) { $0 + $1.removed }
            error = nil
        } catch {
            files = []
            totalAdded = 0
            totalRemoved = 0
            gitRoot = nil
            if let gitError = error as? GitServiceError {
                switch gitError {
                case .notGitRepository:
                    self.error = nil
                default:
                    self.error = error.localizedDescription
                }
            } else {
                self.error = error.localizedDescription
            }
        }
    }

    func undo(path: String) {
        guard let gitRoot else { return }
        do {
            try gitService.restoreFile(gitRoot: gitRoot, path: path)
            let wd = gitRoot
            refresh(workingDirectory: wd)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func undoAll() {
        guard let gitRoot else { return }
        do {
            try gitService.restoreAll(gitRoot: gitRoot)
            let wd = gitRoot
            refresh(workingDirectory: wd)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
