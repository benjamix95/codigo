import Foundation
import Testing

struct AppBundleRustReviewCoreScriptTests {
    @Test
    func validateAppBundleFailsWhenRustReviewCoreDylibIsMissing() throws {
        let root = repoRootURL()
        let scriptURL = root
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("validate_app_bundle.sh")
        let tempRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let appURL = tempRoot.appendingPathComponent("Solo Code.app", isDirectory: true)
        try createMinimalAppBundle(at: appURL, includeRustReviewCore: false)

        let result = try runBashScript(scriptURL, arguments: [appURL.path])

        #expect(result.status == 67)
        #expect(result.stderr.contains("solocode_rust/libsolocode_rust_core.dylib"))
    }

    @Test
    func buildRustSearchBackendFailsClosedWhenBundleOutputIsRequestedWithoutToolchain() throws {
        let root = repoRootURL()
        let scriptURL = root
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("build_rust_search_backend.sh")
        let tempRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let bundleOutput = tempRoot
            .appendingPathComponent("Solo Code.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("solocode_rust", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleOutput, withIntermediateDirectories: true)

        let result = try runBashScript(
            scriptURL,
            environment: [
                "PATH": "/usr/empty",
                "SRCROOT": root.path,
                "CONFIGURATION": "Debug",
                "SOLOCODE_RUST_REVIEW_CORE_BUNDLE_DIR": bundleOutput.path,
            ]
        )

        #expect(result.status != 0)
        #expect((result.stdout + result.stderr).contains("review core Rust richiesto"))
    }

    private func createMinimalAppBundle(
        at appURL: URL,
        includeRustReviewCore: Bool
    ) throws {
        let fileManager = FileManager.default
        let requiredFiles = [
            "Contents/MacOS/Solo Code",
            "Contents/MacOS/coderide-mcp-server-rust",
            "Contents/MacOS/mcp-lifecycle-backend-rust",
            "Contents/Frameworks/CoderEngine.framework/CoderEngine",
            "Contents/Frameworks/CoderIDEMCPServer.framework/CoderIDEMCPServer",
        ]
        let rustCorePath = "Contents/MacOS/solocode_rust/libsolocode_rust_core.dylib"

        for relativePath in requiredFiles + (includeRustReviewCore ? [rustCorePath] : []) {
            let fileURL = appURL.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            #if os(macOS)
            let created = fileManager.createFile(atPath: fileURL.path, contents: Data())
            #else
            let created = fileManager.createFile(atPath: fileURL.path, contents: Data())
            #endif
            #expect(created)
        }
    }

    private func runBashScript(
        _ scriptURL: URL,
        arguments: [String] = [],
        environment overrides: [String: String] = [:]
    ) throws -> ScriptRunResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(overrides) { _, new in new }
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        return ScriptRunResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        return directory
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct ScriptRunResult {
    let status: Int32
    let stdout: String
    let stderr: String
}
