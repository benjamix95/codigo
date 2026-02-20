import SwiftUI
import CoderEngine

@MainActor
final class GeminiStateStore: ObservableObject {
    @Published var status: GeminiStatus = GeminiStatus(isInstalled: false, path: nil, isLoggedIn: false, authMethod: nil)
    @AppStorage("gemini_cli_path") private var storedPath = ""

    init() {
        refresh()
    }

    func refresh() {
        let path = storedPath.isEmpty ? nil : storedPath
        status = GeminiDetector.detect(customPath: path)
    }
}
