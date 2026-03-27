import XCTest

final class SoloCodeValidateScriptTests: XCTestCase {
    func testCiFullDoesNotCrashWhenTouchedFilesAreEmpty() throws {
        let workspace = try makeWorkspace()

        let result = try runValidate(
            arguments: ["--trigger", "ciFull", "--workspace", workspace.path, "--format", "text"],
            in: workspace
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Validation passed for ciFull"), result.output)
        let xcodebuildLog = try readXcodebuildLog(in: workspace)
        XCTAssertTrue(xcodebuildLog.contains("-scheme Solo Code-Release"), xcodebuildLog)
        XCTAssertTrue(xcodebuildLog.contains("-derivedDataPath"), xcodebuildLog)
        XCTAssertTrue(xcodebuildLog.contains("-clonedSourcePackagesDirPath"), xcodebuildLog)
    }

    func testNativeOnlyValidationDoesNotCrashWhenTargetedTestArgsStayEmpty() throws {
        let workspace = try makeWorkspace()
        let nativeFile = workspace.appendingPathComponent("Native/AppCoreRust/src/lib.rs")
        try FileManager.default.createDirectory(at: nativeFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "pub fn smoke() {}".write(to: nativeFile, atomically: true, encoding: .utf8)

        let result = try runValidate(
            arguments: [
                "--trigger", "gitCommit",
                "--workspace", workspace.path,
                "--files", "Native/AppCoreRust/src/lib.rs",
                "--format", "text",
            ],
            in: workspace
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("[SKIPPED] targetedTests"), result.output)
        XCTAssertTrue(result.output.contains("[SKIPPED] build"), result.output)
        XCTAssertTrue(result.output.contains("Validation passed for gitCommit"), result.output)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: workspace.appendingPathComponent("solocode-validate-script-xcodebuild.log").path
            )
        )
    }

    func testTargetedValidationUsesBuildForTestingWithoutRedundantBuildAndKeepsParallelTestingEnabled() throws {
        let workspace = try makeWorkspace()
        let runtimeFile = workspace.appendingPathComponent("App/SoloCodeApp/Sources/Runtime/Example.swift")
        try FileManager.default.createDirectory(
            at: runtimeFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "struct Example {}".write(to: runtimeFile, atomically: true, encoding: .utf8)

        let result = try runValidate(
            arguments: [
                "--trigger", "gitCommit",
                "--workspace", workspace.path,
                "--files", "App/SoloCodeApp/Sources/Runtime/Example.swift",
                "--format", "text",
            ],
            in: workspace
        )

        XCTAssertEqual(result.status, 0, result.output)
        let xcodebuildLog = try readXcodebuildLog(in: workspace)
        XCTAssertTrue(xcodebuildLog.contains("xcodebuild build-for-testing "), xcodebuildLog)
        XCTAssertTrue(xcodebuildLog.contains("xcodebuild test-without-building "), xcodebuildLog)
        XCTAssertTrue(xcodebuildLog.contains("-parallel-testing-enabled YES"), xcodebuildLog)
        XCTAssertFalse(xcodebuildLog.contains("xcodebuild build -workspace"), xcodebuildLog)
    }

    func testWarmPackageCacheSkipsResolvePackageDependenciesOnSecondValidationRun() throws {
        let workspace = try makeWorkspace()
        let runtimeFile = workspace.appendingPathComponent("App/SoloCodeApp/Sources/Runtime/Example.swift")
        try FileManager.default.createDirectory(
            at: runtimeFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "struct Example {}".write(to: runtimeFile, atomically: true, encoding: .utf8)

        _ = try runValidate(
            arguments: [
                "--trigger", "gitCommit",
                "--workspace", workspace.path,
                "--files", "App/SoloCodeApp/Sources/Runtime/Example.swift",
                "--format", "text",
            ],
            in: workspace
        )
        try FileManager.default.removeItem(
            at: workspace.appendingPathComponent("solocode-validate-script-xcodebuild.log")
        )

        let secondRun = try runValidate(
            arguments: [
                "--trigger", "gitCommit",
                "--workspace", workspace.path,
                "--files", "App/SoloCodeApp/Sources/Runtime/Example.swift",
                "--format", "text",
            ],
            in: workspace
        )

        XCTAssertEqual(secondRun.status, 0, secondRun.output)
        XCTAssertTrue(secondRun.output.contains("[SKIPPED] packageResolve"), secondRun.output)
        let xcodebuildLog = try readXcodebuildLog(in: workspace)
        XCTAssertFalse(xcodebuildLog.contains("-resolvePackageDependencies"), xcodebuildLog)
    }

    private func makeWorkspace() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("solocode-validate-script-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("scripts/lib"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs/bugs"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Tests/SoloCodeIntegrationTests"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Native/AppCoreRust/src"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Solo Code.xcworkspace"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Solo Code.xcworkspace/xcshareddata/swiftpm"),
            withIntermediateDirectories: true
        )
        try "{}".write(
            to: root.appendingPathComponent("Solo Code.xcworkspace/xcshareddata/swiftpm/Package.resolved"),
            atomically: true,
            encoding: .utf8
        )

        let sourceScript = repositoryRoot().appendingPathComponent("scripts/solocode-validate")
        let scriptDestination = root.appendingPathComponent("scripts/solocode-validate")
        try FileManager.default.copyItem(at: sourceScript, to: scriptDestination)
        try makeExecutable(scriptDestination)
        let sourceHelper = repositoryRoot().appendingPathComponent("scripts/lib/solocode-validate-xcode.sh")
        let helperDestination = root.appendingPathComponent("scripts/lib/solocode-validate-xcode.sh")
        try FileManager.default.copyItem(at: sourceHelper, to: helperDestination)
        try makeExecutable(helperDestination)
        let sourceFilesHelper = repositoryRoot().appendingPathComponent("scripts/lib/solocode-validate-files.sh")
        let filesHelperDestination = root.appendingPathComponent("scripts/lib/solocode-validate-files.sh")
        try FileManager.default.copyItem(at: sourceFilesHelper, to: filesHelperDestination)
        try makeExecutable(filesHelperDestination)

        try writeExecutable(
            """
            #!/usr/bin/env bash
            exit 0
            """,
            to: root.appendingPathComponent("scripts/validate_rust_cutover_boundary.sh")
        )
        try writeExecutable(
            """
            #!/usr/bin/env bash
            exit 0
            """,
            to: root.appendingPathComponent("scripts/bootstrap_test_bundles.sh")
        )
        try writeExecutable(
            """
            #!/usr/bin/env bash
            echo "xcodebuild $*" >> "${PWD}/solocode-validate-script-xcodebuild.log"
            exit 0
            """,
            to: root.appendingPathComponent("bin/xcodebuild")
        )

        return root
    }

    private func readXcodebuildLog(in workspace: URL) throws -> String {
        try String(
            contentsOf: workspace.appendingPathComponent("solocode-validate-script-xcodebuild.log"),
            encoding: .utf8
        )
    }

    private func runValidate(arguments: [String], in workspace: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/solocode-validate"] + arguments
        process.currentDirectoryURL = workspace

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(workspace.appendingPathComponent("bin").path):/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["SOLOCODE_VALIDATE_DERIVED_DATA_PATH"] = workspace.appendingPathComponent("DerivedDataCache").path
        environment["SOLOCODE_VALIDATE_SOURCE_PACKAGES_DIR"] = workspace.appendingPathComponent("SourcePackagesCache").path
        environment["SOLOCODE_VALIDATE_PACKAGE_RESOLVE_STAMP"] = workspace
            .appendingPathComponent("ValidationCache/package-resolve.stamp").path
        environment["SOLOCODE_VALIDATE_PACKAGE_CACHE_MARKER"] = workspace
            .appendingPathComponent("SourcePackagesCache/.solocode-validate-ready").path
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func writeExecutable(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
        try makeExecutable(url)
    }

    private func makeExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
