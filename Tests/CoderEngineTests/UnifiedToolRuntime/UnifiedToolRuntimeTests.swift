import XCTest
@testable import CoderEngine

final class UnifiedToolRuntimeTests: XCTestCase {
    func makeTmpWorkspace() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("codigo-tests-\(UUID().uuidString)", isDirectory: true)
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
}
