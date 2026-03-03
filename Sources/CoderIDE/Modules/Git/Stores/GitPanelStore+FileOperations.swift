import Foundation

@MainActor
extension GitPanelStore {
    // MARK: - File Undo
    func undo(path: String) {
        guard let gitRoot else { return }
        do {
            try gitService.restoreFile(gitRoot: gitRoot, path: path)
            refresh(workingDirectory: gitRoot)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func undoAll() {
        guard let gitRoot else { return }
        do {
            try gitService.restoreAll(gitRoot: gitRoot)
            refresh(workingDirectory: gitRoot)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stageFile(path: String) {
        guard let gitRoot else { return }
        do {
            try gitService.stageFile(path: path, gitRoot: gitRoot)
            refresh(workingDirectory: gitRoot)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func unstageFile(path: String) {
        guard let gitRoot else { return }
        do {
            try gitService.unstageFile(path: path, gitRoot: gitRoot)
            refresh(workingDirectory: gitRoot)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stageAll() {
        guard let gitRoot else { return }
        do {
            try gitService.stageAll(gitRoot: gitRoot)
            refresh(workingDirectory: gitRoot)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func unstageAll() {
        guard let gitRoot else { return }
        do {
            try gitService.unstageAll(gitRoot: gitRoot)
            refresh(workingDirectory: gitRoot)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
