import Foundation

enum AppBundleSigner {
    static func signAdHocIfPossible(appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = codesignArguments(appPath: appURL.path)

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
                domain: "Codigo.AppBundleSigner",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: message?.isEmpty == false
                        ? message!
                        : "codesign failed for \(appURL.path)"
                ]
            )
        }
    }

    static func codesignArguments(appPath: String) -> [String] {
        ["--force", "--deep", "-s", "-", appPath]
    }
}
