import Foundation

@MainActor
extension GitPanelStore {
    // MARK: - Pull & Fetch
    func pull() {
        guard let gitRoot else { return }
        isBusy = true
        error = nil
        successMessage = nil
        Task {
            do {
                _ = try gitService.pull(gitRoot: gitRoot)
                await MainActor.run {
                    successMessage = "Pull completed"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }

    func fetch() {
        guard let gitRoot else { return }
        isBusy = true
        error = nil
        successMessage = nil
        Task {
            do {
                _ = try gitService.fetch(gitRoot: gitRoot)
                await MainActor.run {
                    successMessage = "Fetch completed"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }
}
