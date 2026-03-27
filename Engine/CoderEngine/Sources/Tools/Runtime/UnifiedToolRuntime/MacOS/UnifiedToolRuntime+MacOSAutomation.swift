import Foundation

extension UnifiedToolRuntime {
    func executeMacOSFocusApp(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = macOSAutomationBridge else {
            return failure("macOS automation bridge not available", errorCode: "transport", startDate: startDate)
        }
        let appName = nonEmpty(call.args["app_name"])
        let bundleID = nonEmpty(call.args["bundle_id"])
        let focused = await bridge.focusApp(appName: appName, bundleID: bundleID)
        if focused {
            return success([
                "title": "App focused",
                "detail": bundleID ?? appName ?? "Host app",
                "output": "Focused \(bundleID ?? appName ?? "host app")"
            ], startDate: startDate)
        }
        return failure(
            "Unable to focus target app",
            errorCode: "runtime",
            startDate: startDate,
            payload: ["title": "Focus failed"]
        )
    }

    func executeMacOSCaptureScreenshot(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = macOSAutomationBridge else {
            return failure("macOS automation bridge not available", errorCode: "transport", startDate: startDate)
        }
        let target = normalizedMacOSCaptureTarget(call.args["target"])
        let appName = nonEmpty(call.args["app_name"])
        let bundleID = nonEmpty(call.args["bundle_id"])
        guard let pngData = await bridge.captureScreenshot(target: target, appName: appName, bundleID: bundleID) else {
            return failure(
                "Failed to capture macOS screenshot",
                errorCode: "runtime",
                startDate: startDate,
                payload: ["title": "Screenshot failed"]
            )
        }
        let base64 = pngData.base64EncodedString()
        return success([
            "title": "macOS screenshot captured",
            "detail": "\(max(1, pngData.count / 1024))KB PNG • \(target)",
            "output": "data:image/png;base64,\(base64)"
        ], startDate: startDate)
    }

    func executeMacOSRunAppleScript(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = macOSAutomationBridge else {
            return failure("macOS automation bridge not available", errorCode: "transport", startDate: startDate)
        }
        let script = (call.args["script"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else {
            return failure("script is required", errorCode: "validation", startDate: startDate)
        }
        let appName = nonEmpty(call.args["app_name"])
        let bundleID = nonEmpty(call.args["bundle_id"])
        let timeoutMs = Int(call.args["timeout_ms"] ?? "")
        let result = await bridge.runAppleScript(script, appName: appName, bundleID: bundleID, timeoutMs: timeoutMs)
        switch result {
        case .success(let output):
            return success([
                "title": "AppleScript executed",
                "detail": bundleID ?? appName ?? "No explicit target",
                "output": output.isEmpty ? "(no output)" : output
            ], startDate: startDate)
        case .failure(let error):
            return failure(
                error.localizedDescription,
                errorCode: "runtime",
                startDate: startDate,
                payload: ["title": "AppleScript failed"]
            )
        }
    }

    func executeMacOSClick(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = macOSAutomationBridge else {
            return failure("macOS automation bridge not available", errorCode: "transport", startDate: startDate)
        }
        guard let x = Double(call.args["x"] ?? ""),
              let y = Double(call.args["y"] ?? "") else {
            return failure("x and y are required", errorCode: "validation", startDate: startDate)
        }
        let clicked = await bridge.click(x: x, y: y)
        if clicked {
            return success([
                "title": "macOS click sent",
                "detail": "\(Int(x)),\(Int(y))",
                "output": "Clicked at (\(Int(x)), \(Int(y)))"
            ], startDate: startDate)
        }
        return failure(
            "Failed to send native click event. Check Accessibility permissions for Solo Code.",
            errorCode: "runtime",
            startDate: startDate,
            payload: ["title": "Click failed"]
        )
    }

    func executeMacOSPressKey(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = macOSAutomationBridge else {
            return failure("macOS automation bridge not available", errorCode: "transport", startDate: startDate)
        }
        let key = (call.args["key"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return failure("key is required", errorCode: "validation", startDate: startDate)
        }
        let modifiers = parseMacOSModifierList(call.args["modifiers"])
        let pressed = await bridge.pressKey(key: key, modifiers: modifiers)
        if pressed {
            return success([
                "title": "macOS key press sent",
                "detail": modifiers.isEmpty ? key : "\(modifiers.joined(separator: "+"))+\(key)",
                "output": "Pressed \(modifiers.isEmpty ? key : "\(modifiers.joined(separator: "+"))+\(key)")"
            ], startDate: startDate)
        }
        return failure(
            "Failed to send native key event. Check Accessibility permissions and key name.",
            errorCode: "runtime",
            startDate: startDate,
            payload: ["title": "Key press failed"]
        )
    }

    func executeMacOSTypeText(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = macOSAutomationBridge else {
            return failure("macOS automation bridge not available", errorCode: "transport", startDate: startDate)
        }
        let text = call.args["text"] ?? ""
        guard !text.isEmpty else {
            return failure("text is required", errorCode: "validation", startDate: startDate)
        }
        let typed = await bridge.typeText(text)
        if typed {
            return success([
                "title": "macOS text typed",
                "detail": "\(text.count) characters",
                "output": text
            ], startDate: startDate)
        }
        return failure(
            "Failed to type native text. Check Accessibility permissions.",
            errorCode: "runtime",
            startDate: startDate,
            payload: ["title": "Type text failed"]
        )
    }

    func executeMacOSListUIElements(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = macOSAutomationBridge else {
            return failure("macOS automation bridge not available", errorCode: "transport", startDate: startDate)
        }
        let appName = nonEmpty(call.args["app_name"])
        let bundleID = nonEmpty(call.args["bundle_id"])
        let scope = normalizedMacOSUIScope(call.args["scope"])
        let limit = min(max(Int(call.args["limit"] ?? "") ?? 80, 1), 400)
        let elements = await bridge.listUIElements(appName: appName, bundleID: bundleID, scope: scope, limit: limit)
        guard !elements.isEmpty else {
            return failure(
                "No UI elements found. If this is unexpected, ensure Accessibility permissions are granted and the target app has a visible window.",
                errorCode: "runtime",
                startDate: startDate,
                payload: ["title": "UI inspection empty"]
            )
        }
        return success([
            "title": "UI elements listed",
            "detail": "\(elements.count) elements • \(scope)",
            "output": prettyPrintedMacOSUIElements(elements)
        ], startDate: startDate)
    }

    private func normalizedMacOSCaptureTarget(_ raw: String?) -> String {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "screen":
            return "screen"
        case "app":
            return "app"
        default:
            return "front_window"
        }
    }

    private func normalizedMacOSUIScope(_ raw: String?) -> String {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "entire_app":
            return "entire_app"
        default:
            return "front_window"
        }
    }

    private func parseMacOSModifierList(_ raw: String?) -> [String] {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return []
        }
        if raw.hasPrefix("["),
           let data = raw.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return parsed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        }
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func prettyPrintedMacOSUIElements(_ elements: [MacOSUIElementSnapshot]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(elements),
              let text = String(data: data, encoding: .utf8) else {
            return elements.map {
                "\($0.role) | \($0.name) | \($0.help) | \($0.x),\($0.y) \($0.width)x\($0.height)"
            }.joined(separator: "\n")
        }
        return text
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
