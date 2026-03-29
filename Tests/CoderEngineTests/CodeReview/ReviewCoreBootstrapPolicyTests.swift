import Foundation
import XCTest
@testable import CoderEngine

final class ReviewCoreBootstrapPolicyTests: XCTestCase {
    func testDefersRustBootstrapWhenXCTestEnvironmentIsPresentWithoutExplicitLibraryPath() {
        XCTAssertTrue(
            shouldDeferRustReviewCoreBootstrap(
                environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
            )
        )
    }

    func testDoesNotDeferRustBootstrapWhenExplicitLibraryPathIsProvided() {
        XCTAssertFalse(
            shouldDeferRustReviewCoreBootstrap(
                environment: [
                    "XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration",
                    "SOLOCODE_REVIEW_CORE_LIBRARY_PATH": "/tmp/libsolocode_rust_core.dylib",
                ]
            )
        )
    }

    func testForceSwiftFlagDisablesRustBootstrap() {
        XCTAssertTrue(
            shouldDeferRustReviewCoreBootstrap(
                environment: ["SOLOCODE_REVIEW_CORE_FORCE_SWIFT": "1"]
            )
        )
    }

    func testDoesNotDeferRustBootstrapForNormalAppLaunchEnvironment() {
        XCTAssertFalse(
            shouldDeferRustReviewCoreBootstrap(environment: [:])
        )
    }

    func testDerivedDataFallbackIsDisabledWhenRunningInsideAppBundle() {
        XCTAssertFalse(
            shouldScanDerivedDataForRustReviewCoreFallback(
                environment: [:],
                bundleURL: URL(fileURLWithPath: "/tmp/Solo Code.app", isDirectory: true)
            )
        )
    }

    func testDerivedDataFallbackStaysEnabledForNonAppBundlesWithoutExplicitLibraryPath() {
        XCTAssertTrue(
            shouldScanDerivedDataForRustReviewCoreFallback(
                environment: [:],
                bundleURL: URL(fileURLWithPath: "/tmp/CoderEngineTests.xctest", isDirectory: true)
            )
        )
    }

    func testDerivedDataFallbackIsDisabledWhenExplicitLibraryPathIsProvided() {
        XCTAssertFalse(
            shouldScanDerivedDataForRustReviewCoreFallback(
                environment: ["SOLOCODE_REVIEW_CORE_LIBRARY_PATH": "/tmp/libsolocode_rust_core.dylib"],
                bundleURL: URL(fileURLWithPath: "/tmp/CoderEngineTests.xctest", isDirectory: true)
            )
        )
    }

    func testBuildRustSearchBackendFailsClosedWhenBundleOutputIsRequestedWithoutToolchain() throws {
        let root = repoRootURL()
        let scriptURL = root
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("build_rust_search_backend.sh")
        let tempRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let fakeHome = tempRoot.appendingPathComponent("fake-home", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)

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
                "HOME": fakeHome.path,
                "SRCROOT": root.path,
                "CONFIGURATION": "Debug",
                "SOLOCODE_RUST_REVIEW_CORE_BUNDLE_DIR": bundleOutput.path,
            ]
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue((result.stdout + result.stderr).contains("review core Rust richiesto"))
    }

    func testBuildRustSearchBackendProducesCodesignedBundleLibrary() throws {
        guard commandExists("cargo"), commandExists("rustc") else {
            throw XCTSkip("Toolchain Rust non disponibile in ambiente.")
        }

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

        let buildResult = try runBashScript(
            scriptURL,
            environment: [
                "SRCROOT": root.path,
                "CONFIGURATION": "Debug",
                "SOLOCODE_RUST_REVIEW_CORE_BUNDLE_DIR": bundleOutput.path,
            ]
        )
        XCTAssertEqual(buildResult.status, 0, buildResult.stdout + buildResult.stderr)

        let dylibURL = bundleOutput.appendingPathComponent("libsolocode_rust_core.dylib")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dylibURL.path))

        let verifyResult = try runProcess(
            executablePath: "/usr/bin/codesign",
            arguments: ["--verify", "--verbose=4", dylibURL.path]
        )
        XCTAssertEqual(verifyResult.status, 0, verifyResult.stdout + verifyResult.stderr)
    }

    private func commandExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        return process.terminationStatus == 0
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        return directory
    }

    private func runBashScript(
        _ scriptURL: URL,
        environment overrides: [String: String] = [:]
    ) throws -> ProcessResult {
        try runProcess(
            executablePath: "/bin/bash",
            arguments: [scriptURL.path],
            environment: overrides
        )
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        environment overrides: [String: String] = [:]
    ) throws -> ProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(overrides) { _, new in new }
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }
}

private struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}
