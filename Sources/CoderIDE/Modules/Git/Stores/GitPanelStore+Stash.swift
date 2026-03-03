import Foundation

@MainActor
extension GitPanelStore {
    // MARK: - Stash
    func stash(message: String?) {
        guard let gitRoot else { return }
        isBusy = true
        error = nil
        successMessage = nil
        Task {
            do {
                try gitService.stash(gitRoot: gitRoot, message: message)
                await MainActor.run {
                    successMessage = "Changes stashed"
                    stashMessage = ""
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }

    func stashPop() {
        guard let gitRoot else { return }
        isBusy = true
        error = nil
        successMessage = nil
        Task {
            do {
                try gitService.stashPop(gitRoot: gitRoot)
                await MainActor.run {
                    successMessage = "Stash popped"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }

    func stashDrop(index: Int) {
        guard let gitRoot else { return }
        isBusy = true
        error = nil
        successMessage = nil
        Task {
            do {
                try gitService.stashDrop(gitRoot: gitRoot, index: index)
                await MainActor.run {
                    successMessage = "Stash dropped"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }
}
