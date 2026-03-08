import Foundation

enum AppBundleIconInstaller {
    static let iconFilename = "Codigo.icns"

    @discardableResult
    static func installIfAvailable(
        into resourcesURL: URL,
        workingDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        guard let sourceURL = iconSourceURL(workingDirectoryURL: workingDirectoryURL, fileManager: fileManager) else {
            return false
        }

        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let destinationURL = resourcesURL.appendingPathComponent(iconFilename)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return true
    }

    static func iconSourceURL(
        workingDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let candidates: [URL?] = [
            workingDirectoryURL.appendingPathComponent("Sources/CoderIDE/Resources/\(iconFilename)"),
            RuntimeResourceLocator.appIconURL(),
        ]

        for candidate in candidates {
            guard let candidate, fileManager.fileExists(atPath: candidate.path) else { continue }
            return candidate
        }

        return nil
    }
}
