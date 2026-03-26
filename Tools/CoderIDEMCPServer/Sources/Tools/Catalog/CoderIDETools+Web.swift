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
                    "maxResults": .object(["type": "string", "description": "Maximum number of results (default: 5)"]),
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
                    "url": .object(["type": "string", "description": "URL to fetch"]),
                ]),
                "required": .array([.string("url")]),
            ]),
            annotations: .init(title: "Web Fetch", readOnlyHint: true, openWorldHint: true)
        ),
    ]
}
