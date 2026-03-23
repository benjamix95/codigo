import Foundation

struct EchoToolSafePlugin: IDEExtensionPlugin {
    let manifest = ExtensionManifest(
        id: "com.solocode.extensions.echo-safe",
        name: "Echo Safe Plugin",
        version: "1.0.0",
        entryPoint: "EchoToolSafePlugin",
        capabilities: [.readOnlyTools],
        exposedTools: ["echo.safe"],
        minimumIDEVersion: "1.0.0"
    )

    func onLoad(context: ExtensionRuntimeContext) async throws {
        guard context.isCapabilityAllowed(.readOnlyTools) else {
            throw ExtensionRuntimeError.capabilityDenied(.readOnlyTools)
        }
    }

    func onUnload(context: ExtensionRuntimeContext) async {
        _ = context
    }

    func handle(
        request: ExtensionToolRequest,
        context: ExtensionRuntimeContext
    ) async throws -> ExtensionToolResponse {
        guard context.isCapabilityAllowed(.readOnlyTools) else {
            throw ExtensionRuntimeError.capabilityDenied(.readOnlyTools)
        }
        guard request.tool == "echo.safe" else {
            throw ExtensionRuntimeError.toolNotExposed(pluginId: manifest.id, tool: request.tool)
        }

        let raw = request.payload["message"] ?? ""
        let cleaned = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let output = String(cleaned.prefix(240))
        return ExtensionToolResponse(
            output: output,
            metadata: [
                "plugin_id": manifest.id,
                "tool": request.tool,
                "sanitized": "true",
            ]
        )
    }
}
