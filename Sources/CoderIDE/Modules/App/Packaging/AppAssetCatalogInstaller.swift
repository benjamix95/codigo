import Foundation

enum AppAssetCatalogInstaller {
    static func installIfAvailable(
        into resourcesURL: URL,
        workingDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let sourceURL = workingDirectoryURL
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("CoderIDE", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Assets.xcassets", isDirectory: true)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return false
        }

        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("codigo-actool-\(UUID().uuidString)", isDirectory: true)
        let outputURL = tempRoot.appendingPathComponent("CompiledAssets", isDirectory: true)
        let partialPlistURL = tempRoot.appendingPathComponent("actool-partial.plist")

        try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = actoolArguments(
            sourcePath: sourceURL.path,
            outputPath: outputURL.path,
            partialPlistPath: partialPlistURL.path
        )

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "Codigo.AppAssetCatalogInstaller",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: message?.isEmpty == false
                        ? message!
                        : "actool failed for \(sourceURL.path)"
                ]
            )
        }

        try copyIfPresent(
            named: "Assets.car",
            from: outputURL,
            to: resourcesURL,
            fileManager: fileManager
        )
        try copyIfPresent(
            named: "AppIcon.icns",
            from: outputURL,
            to: resourcesURL,
            fileManager: fileManager
        )
        return true
    }

    static func actoolArguments(
        sourcePath: String,
        outputPath: String,
        partialPlistPath: String
    ) -> [String] {
        [
            "actool",
            sourcePath,
            "--compile", outputPath,
            "--platform", "macosx",
            "--minimum-deployment-target", "14.0",
            "--app-icon", "AppIcon",
            "--output-partial-info-plist", partialPlistPath,
        ]
    }

    private static func copyIfPresent(
        named name: String,
        from sourceDirectory: URL,
        to destinationDirectory: URL,
        fileManager: FileManager
    ) throws {
        let sourceURL = sourceDirectory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        let destinationURL = destinationDirectory.appendingPathComponent(name)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
}
