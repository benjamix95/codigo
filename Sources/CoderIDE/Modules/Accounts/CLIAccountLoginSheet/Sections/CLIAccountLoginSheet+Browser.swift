import Foundation
import AppKit

extension CLIAccountLoginSheet {
    private func refreshAvailableBrowsers() {
        guard let probeURL = URL(string: "https://claude.ai") else { return }
        let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL)
        let defaultBundleId = defaultAppURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: probeURL)

        var seen: Set<String> = []
        var detected: [BrowserApp] = []
        for appURL in appURLs {
            guard let bundle = Bundle(url: appURL) else { continue }
            let bundleId = bundle.bundleIdentifier ?? appURL.path
            guard seen.insert(bundleId).inserted else { continue }
            let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? appURL.deletingPathExtension().lastPathComponent
            detected.append(
                BrowserApp(
                    id: bundleId,
                    name: displayName,
                    url: appURL,
                    isDefault: bundleId == defaultBundleId
                )
            )
        }
        availableBrowsers = detected.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
