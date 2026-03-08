import Foundation

@MainActor
final class PlanHistoryStore: ObservableObject {
    @Published var entries: [PlanHistoryEntry] = []
    @Published var selectedEntryId: UUID?
    private var userDefaultsObserver: NSObjectProtocol?
    let userDefaults: UserDefaults
    let storageURL: URL

    init(
        userDefaults: UserDefaults = .standard,
        storageURL: URL? = nil
    ) {
        self.userDefaults = userDefaults
        self.storageURL = storageURL ?? Self.defaultFileURL
        load()
        applyConfiguredLimits()
        userDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: userDefaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyConfiguredLimits()
            }
        }
    }

    deinit {
        if let observer = userDefaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
