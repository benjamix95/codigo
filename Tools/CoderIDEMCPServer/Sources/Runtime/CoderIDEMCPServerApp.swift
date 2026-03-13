import Foundation

public struct CoderIDEMCPServerApp {
    public static func main() async throws {
        throw MCPServerSwiftRuntimeRetiredError()
    }
}

struct MCPServerSwiftRuntimeRetiredError: LocalizedError {
    var errorDescription: String? {
        "Il runtime MCP Swift legacy e' stato ritirato. Usa il binario coderide-mcp-server-rust."
    }
}
