import SwiftUI
import CoderEngine

@MainActor
final class GeminiStateStore: ObservableObject {
    @Published var status: GeminiStatus = GeminiStatus(isInstalled: false, path: nil, isLoggedIn: false, authMethod: nil)
    @AppStorage("gemini_cli_path") private var storedPath = ""

    init() {
        // Defer detection to avoid running Process.waitUntilExit() during
        // SwiftUI graph construction, which can trigger AttributeGraph preconditions.
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        let path = storedPath.isEmpty ? nil : storedPath
        // Run blocking detection off the main thread.
        Task.detached(priority: .utility) { [path] in
            let result = GeminiDetector.detect(customPath: path)
            await MainActor.run { [weak self] in
                self?.status = result
            }
        }
    }
}
