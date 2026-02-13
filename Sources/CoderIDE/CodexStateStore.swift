import SwiftUI
import CoderEngine

@MainActor
final class CodexStateStore: ObservableObject {
    @Published var status: CodexStatus = CodexStatus(isInstalled: false, path: nil, isLoggedIn: false, authMethod: nil)
    @AppStorage("codex_path") private var storedPath = ""

    init() {
        refresh()
    }

    func refresh() {
        let path = storedPath.isEmpty ? nil : storedPath
        status = CodexDetector.detect(customPath: path)
    }
}
