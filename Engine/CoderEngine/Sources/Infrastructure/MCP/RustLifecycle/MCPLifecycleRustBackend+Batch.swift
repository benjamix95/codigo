import Foundation

extension MCPLifecycleRustBackend {
    func callToolsBatch(
        calls: [MCPLifecycleRustBatchCallRequestItem]
    ) async throws -> MCPLifecycleRustBatchCallPayload {
        try await request(
            op: "call_tools_batch",
            payload: ["calls": calls.map(\.jsonObject)]
        )
    }
}
