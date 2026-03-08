import Foundation

extension OpenAIAPIProvider {
    static var toolDefinitions: [[String: Any]] {
        ToolSchemaCatalog.openAIFunctionTools
    }

    static var responseToolDefinitions: [[String: Any]] {
        toolDefinitions.compactMap { entry in
            let type = (entry["type"] as? String ?? "").lowercased()
            if type == "function", let function = entry["function"] as? [String: Any] {
                var normalized = function
                normalized["type"] = "function"
                return normalized
            }
            return entry
        }
    }
}
