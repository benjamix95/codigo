import CoderEngine
import Foundation

@MainActor
extension GitPanelStore {
    func notifyBugHunterForCommit(_ commit: GitCommitResult, gitRoot: String) {
        postCommitBugHunterObserver?(commit, gitRoot)
    }
}
