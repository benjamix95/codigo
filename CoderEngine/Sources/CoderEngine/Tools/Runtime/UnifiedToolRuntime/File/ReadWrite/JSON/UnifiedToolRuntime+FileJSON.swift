import Foundation

extension UnifiedToolRuntime {
    func executeReadJSON(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"], context: context)
        let content = try String(contentsOfFile: path, encoding: .utf8)
        guard let data = content.data(using: .utf8) else {
            throw ToolRuntimeError.validation("JSON cannot be read")
        }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ToolRuntimeError.validation("Invalid JSON")
        }
        let pretty = prettyJSON(obj)
        return success([
            "title": "Read JSON \(path)",
            "path": path,
            "output": truncate(pretty, maxBytes: context.policy.maxReadBytesPerFile)
        ], startDate: startDate)
    }

    func executeWriteJSON(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"], context: context)
        guard let patchRaw = call.args["patch"], !patchRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolRuntimeError.validation("patch JSON is required")
        }
        let patchObj = try parseJSONObject(from: patchRaw)
        let existingObj: Any
        if FileManager.default.fileExists(atPath: path) {
            let existingData = try Data(contentsOf: URL(fileURLWithPath: path))
            existingObj = try JSONSerialization.jsonObject(with: existingData)
        } else {
            existingObj = [String: Any]()
        }
        guard var merged = existingObj as? [String: Any] else {
            throw ToolRuntimeError.validation("write_json supports only JSON object root")
        }
        if let patchDict = patchObj as? [String: Any] {
            for (k, v) in patchDict { merged[k] = v }
        } else {
            throw ToolRuntimeError.validation("patch must be a JSON object")
        }
        let output = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: URL(fileURLWithPath: path), options: .atomic)
        return success([
            "title": "Write JSON \(path)",
            "path": path,
            "detail": "Patch applied",
            "output": String(data: output, encoding: .utf8) ?? ""
        ], startDate: startDate)
    }
}
