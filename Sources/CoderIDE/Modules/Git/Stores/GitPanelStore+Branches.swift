import Foundation
import CoderEngine

@MainActor
extension GitPanelStore {
    // MARK: - Branch Operations
    func switchBranch(_ name: String) {
        guard let gitRoot else { return }
        isBusy = true
        error = nil
        successMessage = nil
        Task {
            do {
                try gitService.checkoutBranch(name: name, gitRoot: gitRoot)
                await MainActor.run {
                    successMessage = "Branch: \(name)"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isBusy = false
                }
            }
        }
    }

    func createAndCheckoutBranch() {
        guard let gitRoot else { return }
        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isBusy = true
        error = nil
        successMessage = nil
        Task {
            do {
                try gitService.createAndCheckoutBranch(name: name, gitRoot: gitRoot)
                await MainActor.run {
                    successMessage = "Branch created: \(name)"
                    showCreateBranch = false
                    newBranchName = ""
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isBusy = false
                }
            }
        }
    }

    func deleteBranch(name: String, force: Bool) {
        guard let gitRoot else { return }
        isBusy = true
        error = nil
        successMessage = nil
        Task {
            do {
                try gitService.deleteBranch(name: name, gitRoot: gitRoot, force: force)
                await MainActor.run {
                    successMessage = "Branch deleted: \(name)"
                    showDeleteBranchConfirm = false
                    branchToDelete = nil
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }

    func renameBranch(oldName: String, newName: String) {
        guard let gitRoot else { return }
        isBusy = true
        error = nil
        successMessage = nil
        Task {
            do {
                try gitService.renameBranch(oldName: oldName, newName: newName, gitRoot: gitRoot)
                await MainActor.run {
                    successMessage = "Branch renamed: \(oldName) → \(newName)"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }

    func checkoutRemoteBranch(name: String) {
        guard let gitRoot else { return }
        isBusy = true
        error = nil
        successMessage = nil
        Task {
            do {
                try gitService.checkoutRemoteBranch(name: name, gitRoot: gitRoot)
                await MainActor.run {
                    successMessage = "Checked out: \(name)"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }
}
