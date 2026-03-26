import SwiftUI
import CoderEngine

@MainActor
final class KiloStateStore: ObservableObject {
    @Published var status: KiloStatus = KiloStatus(isInstalled: false, path: nil, hasCredentials: false)
    @AppStorage("kilo_path") private var storedPath = ""

    init() {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        let path = storedPath.isEmpty ? nil : storedPath
        Task.detached(priority: .utility) { [path] in
            let result = KiloDetector.detect(customPath: path)
            Task { @MainActor [weak self] in
                self?.status = result
            }
        }
    }
}
