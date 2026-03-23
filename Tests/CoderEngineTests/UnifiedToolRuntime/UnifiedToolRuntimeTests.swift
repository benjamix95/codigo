import XCTest
@testable import CoderEngine

final class UnifiedToolRuntimeTests: XCTestCase {
    func makeTmpWorkspace() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("solocode-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    func extractLastPayload(_ events: [StreamEvent]) -> [String: String]? {
        for event in events.reversed() {
            if case .raw(_, let payload) = event {
                return payload
            }
        }
        return nil
    }

    func makeCall(
        name: String,
        args: [String: String] = [:],
        workspace: URL? = nil
    ) -> (ToolCall, ToolExecutionContext) {
        let ws = workspace ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let call = ToolCall(
            id: UUID().uuidString,
            name: name,
            args: args,
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: ws))
        return (call, ctx)
    }

    @discardableResult
    func writeValidationConfig(in workspace: URL) throws -> URL {
        let configDir = workspace.appendingPathComponent("Config/validation", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let configURL = configDir.appendingPathComponent("solocode-validation.json")
        let config = """
        {
          "version": 1,
          "workspace": "Solo Code.xcworkspace",
          "localScheme": "Solo Code-Debug",
          "releaseScheme": "Solo Code-Release",
          "destination": "platform=macOS",
          "testPlan": null,
          "codeFileGlobs": ["App/**/*.swift","Engine/**/*.swift","Tools/**/*.swift","Tests/**/*.swift"],
          "excludedCodePaths": [],
          "securitySensitivePrefixes": [],
          "testGroups": [
            {
              "id": "engine-tools",
              "bundle": "CoderEngineTests",
              "pathPrefixes": ["Engine/CoderEngine/Sources/Tools/", "Tools/CoderIDEMCPServer/Sources/"],
              "onlyTesting": ["CoderEngineTests/UnifiedToolRuntime"]
            },
            {
              "id": "app-runtime",
              "bundle": "SoloCodeAppTests",
              "pathPrefixes": ["App/SoloCodeApp/Sources/"],
              "onlyTesting": ["SoloCodeAppTests/DebugFlowToolE2ETests"]
            }
          ]
        }
        """
        try config.write(to: configURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("Solo Code.xcworkspace"), withIntermediateDirectories: true)
        return configURL
    }

    @discardableResult
    func makeFakeXcodebuild(in workspace: URL, script: String) throws -> URL {
        let binDir = workspace.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let scriptURL = binDir.appendingPathComponent("xcodebuild")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }
}
