import CoderEngine
import Foundation
import MCP

extension CoderIDETools {
    /// Allinea MCP Swift al server Rust: uno `Tool` per ogni voce in `ReviewAuditToolName.allToolNames`.
    static let auditTools: [Tool] = ReviewAuditToolName.allToolNames.map { makeAuditTool(suffix: $0) }

    private static func makeAuditTool(suffix: String) -> Tool {
        let title = "Audit \(suffix.replacingOccurrences(of: "_", with: " "))"
        return Tool(
            name: "coderide_\(suffix)",
            description: "Structured workspace audit scoped to files or directories (\(suffix)).",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "scope_files": .object([
                        "type": "string",
                        "description": "Optional JSON array or comma-separated list of scoped files.",
                    ]),
                    "path": .object([
                        "type": "string",
                        "description": "Optional file or directory scope.",
                    ]),
                ]),
            ]),
            annotations: .init(title: title, readOnlyHint: true, idempotentHint: true)
        )
    }
}
