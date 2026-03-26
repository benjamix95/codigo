import SwiftUI
import CoderEngine

@MainActor
final class CodexStateStore: ObservableObject {
    @Published var status: CodexStatus = CodexStatus(isInstalled: false, path: nil, isLoggedIn: false, authMethod: nil)
    @AppStorage("codex_path") private var storedPath = ""

    init() {
        // Defer detection to avoid running Process.waitUntilExit() during
        // SwiftUI graph construction, which pumps the run loop and crashes
        // AttributeGraph with a precondition failure.
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        let path = storedPath.isEmpty ? nil : storedPath
        // Run the blocking detection off the main thread.
        Task.detached(priority: .utility) { [path] in
            let result = CodexDetector.detect(customPath: path)
            Task { @MainActor [weak self] in
                self?.status = result
            }
        }
    }
}
