import Foundation

@MainActor
extension AppUpdateCenter {
    func shouldCheckNow() -> Bool {
        let latestDate = lastCheckedAt ?? userDefaults.object(forKey: Self.lastCheckedKey) as? Date
        if latestDate == nil { return true }
        let elapsed = Date().timeIntervalSince(latestDate!)
        return elapsed >= Self.checkInterval
    }

    func updateLastChecked() {
        let now = Date()
        lastCheckedAt = now
        userDefaults.set(now, forKey: Self.lastCheckedKey)
    }

    func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw NSError(
                domain: "AppUpdateCenter",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server response."]
            )
        }
        guard (200...299).contains(response.statusCode) else {
            throw NSError(
                domain: "AppUpdateCenter",
                code: response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Errore server: \(response.statusCode)."]
            )
        }
    }
}
