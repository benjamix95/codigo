import Foundation
import MCP

extension CoderIDETools {
    static let webTools: [Tool] = [
        // --- Web ---
        Tool(
            name: "coderide_web_search",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_web_search", fallback: "Search the web for information."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object(["type": "string", "description": "Search query"]),
                    "explanation": .object(["type": "string", "description": "Optional rationale for the search"]),
                    "timeout": .object([
                        "type": "number",
                        "description": "Max seconds for the HTTP request (0 < timeout ≤ 120; fractional allowed; invalid values default to 30)"
                    ]),
                ]),
                "required": .array([.string("query")]),
            ]),
            annotations: .init(title: "Web Search", readOnlyHint: true, openWorldHint: true)
        ),
        Tool(
            name: "coderide_web_fetch",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_web_fetch", fallback: "Fetch a web page and convert it to readable Markdown."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "url": .object(["type": "string", "description": "URL to fetch (https added if scheme omitted)"]),
                    "timeout": .object([
                        "type": "number",
                        "description": "Max seconds for the HTTP request (0 < timeout ≤ 120; fractional allowed; invalid values default to 30)"
                    ]),
                ]),
                "required": .array([.string("url")]),
            ]),
            annotations: .init(title: "Web Fetch", readOnlyHint: true, openWorldHint: true)
        ),
    ]
}
