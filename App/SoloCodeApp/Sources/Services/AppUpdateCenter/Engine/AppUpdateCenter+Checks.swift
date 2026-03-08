import Foundation

@MainActor
extension AppUpdateCenter {
    func checkForUpdates(force: Bool = false) async {
        guard isUpdateCheckEnabled else {
            state = .disabled
            availableUpdate = nil
            return
        }

        if !force && !shouldCheckNow() {
            if state == .idle || state == .disabled {
                state = .upToDate
            }
            return
        }

        guard let manifestURL = Self.validatedHTTPSURL(from: manifestURL) else {
            lastError = "Manifest URL must be a valid HTTPS URL."
            state = .failed(lastError ?? "")
            availableUpdate = nil
            return
        }

        state = .checking
        lastError = nil

        do {
            let request = URLRequest(url: manifestURL, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 8)
            let (data, response) = try await urlSession.data(for: request)

            try validate(response: response)

            let decoder = JSONDecoder()
            let manifest = try decoder.decode(AppUpdateManifest.self, from: data)
            let localVersion = currentVersion()
            let localBuild = currentBuild()

            guard manifest.version.isEmpty == false else {
                throw NSError(
                    domain: "AppUpdateCenter",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: "Manifest mancante della versione."]
                )
            }

            guard AppUpdateCenter.isCompatible(with: manifest.minimumSystemVersion) else {
                throw NSError(
                    domain: "AppUpdateCenter",
                    code: 1002,
                    userInfo: [NSLocalizedDescriptionKey: "Update not compatible with this macOS version."]
                )
            }

            if AppUpdateCenter.shouldUpdate(localVersion: localVersion, localBuild: localBuild, manifest: manifest) {
                availableUpdate = manifest
                lastError = nil
                state = .available(manifest)
            } else {
                availableUpdate = nil
                state = .upToDate
            }

            // Persisti il timestamp solo su check validato e decodificato con successo.
            updateLastChecked()
            userDefaults.set(manifest.version, forKey: Self.updateVersionKey)
            userDefaults.set(manifest.shortNotes, forKey: "\(Self.updateVersionKey)_last_notes")
        } catch {
            let message = error.localizedDescription
            logger.error("Update check failed: \(message)")
            lastError = message
            state = .failed(message)
            availableUpdate = nil
        }
    }

    nonisolated static func shouldUpdate(localVersion: String, localBuild: String, manifest: AppUpdateManifest) -> Bool {
        guard
            let localParsed = AppVersion(localVersion),
            let remoteParsed = AppVersion(manifest.version)
        else {
            return false
        }

        if remoteParsed > localParsed { return true }
        guard remoteParsed == localParsed else { return false }
        guard
            let localBuildInt = Int(localBuild),
            let remoteBuildInt = Int(manifest.displayBuild)
        else {
            return false
        }
        return remoteBuildInt > localBuildInt
    }

    nonisolated static func isCompatible(with minimumSystemVersion: String?) -> Bool {
        guard
            let minimumSystemVersion,
            let minimumParsed = AppVersion(minimumSystemVersion)
        else {
            return true
        }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        guard let current = AppVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)") else {
            return true
        }
        return current >= minimumParsed
    }
}
