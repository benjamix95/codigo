import Foundation

extension AnthropicAPIProvider {
    static var toolDefinitions: [[String: Any]] {
        ToolSchemaCatalog.anthropicTools
    }
}
