import XCTest
@testable import CoderIDE
import CoderEngine

final class ExtensionRuntimeTests: XCTestCase {
    func testRuntimeLoadsExecutesAndUnloadsEchoPlugin() async throws {
        let runtime = ExtensionRuntime(
            configuration: ExtensionRuntimeConfiguration(
                runtimeEnabled: true,
                allowedCapabilities: [.readOnlyTools, .readWorkspace]
            )
        )

        let loaded = try await runtime.load(
            plugin: EchoToolSafePlugin(),
            workspaceRoots: ["/tmp/workspace"]
        )
        XCTAssertEqual(loaded.pluginId, "com.codigo.extensions.echo-safe")
        XCTAssertTrue(loaded.exposedTools.contains("echo.safe"))

        let response = try await runtime.execute(
            pluginId: loaded.pluginId,
            tool: "echo.safe",
            payload: ["message": "  ciao\nmondo  "]
        )
        XCTAssertEqual(response.output, "ciao mondo")
        XCTAssertEqual(response.metadata["sanitized"], "true")

        try await runtime.unload(pluginId: loaded.pluginId)
        let afterUnload = await runtime.listLoadedExtensions()
        XCTAssertTrue(afterUnload.isEmpty)
    }

    func testRuntimeRejectsToolNotExposedAtExecuteTime() async throws {
        let runtime = ExtensionRuntime(
            configuration: ExtensionRuntimeConfiguration(
                runtimeEnabled: true,
                allowedCapabilities: [.readOnlyTools]
            )
        )

        let loaded = try await runtime.load(
            plugin: EchoToolSafePlugin(),
            workspaceRoots: ["/tmp/workspace"]
        )

        do {
            _ = try await runtime.execute(
                pluginId: loaded.pluginId,
                tool: "echo.unsafe",
                payload: ["message": "ciao"]
            )
            XCTFail("Expected tool not exposed")
        } catch let error as ExtensionRuntimeError {
            XCTAssertEqual(
                error,
                .toolNotExposed(pluginId: loaded.pluginId, tool: "echo.unsafe")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRuntimeRejectsDeniedCapability() async {
        let runtime = ExtensionRuntime(
            configuration: ExtensionRuntimeConfiguration(
                runtimeEnabled: true,
                allowedCapabilities: [.readOnlyTools]
            )
        )
        let plugin = DangerousWritePlugin()

        do {
            _ = try await runtime.load(plugin: plugin, workspaceRoots: ["/tmp/workspace"])
            XCTFail("Expected capability denied")
        } catch let error as ExtensionRuntimeError {
            XCTAssertEqual(error, .capabilityDenied(.writeWorkspace))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRuntimeDisabledBlocksLoad() async {
        let runtime = ExtensionRuntime(
            configuration: ExtensionRuntimeConfiguration(
                runtimeEnabled: false,
                allowedCapabilities: [.readOnlyTools]
            )
        )

        do {
            _ = try await runtime.load(plugin: EchoToolSafePlugin(), workspaceRoots: [])
            XCTFail("Expected runtime disabled")
        } catch let error as ExtensionRuntimeError {
            XCTAssertEqual(error, .runtimeDisabled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRuntimeRejectsUnloadForUnknownPlugin() async {
        let runtime = ExtensionRuntime(
            configuration: ExtensionRuntimeConfiguration(
                runtimeEnabled: true,
                allowedCapabilities: [.readOnlyTools]
            )
        )

        do {
            try await runtime.unload(pluginId: "missing.plugin")
            XCTFail("Expected plugin not loaded")
        } catch let error as ExtensionRuntimeError {
            XCTAssertEqual(error, .pluginNotLoaded("missing.plugin"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRuntimeRejectsMinimumIDEVersionAboveCurrentVersion() async {
        let runtime = ExtensionRuntime(
            configuration: ExtensionRuntimeConfiguration(
                runtimeEnabled: true,
                allowedCapabilities: [.readOnlyTools, .readWorkspace],
                currentIDEVersion: "0.9.0"
            )
        )

        do {
            _ = try await runtime.load(plugin: EchoToolSafePlugin(), workspaceRoots: [])
            XCTFail("Expected minimum IDE version rejection")
        } catch let error as ExtensionRuntimeError {
            XCTAssertEqual(
                error,
                .minimumIDEVersionNotSatisfied(required: "1.0.0", current: "0.9.0")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExtensionManifestDecodesLegacyContractKeys() throws {
        let data = Data(
            """
            {
              "id": "com.codigo.extensions.legacy",
              "name": "Legacy Contract",
              "version": "1.0.0",
              "entrypoint": "plugin.js",
              "capabilities": ["read", "web"],
              "allowedTools": ["echo.safe"],
              "minimumIDEVersion": "1.2.0"
            }
            """.utf8
        )

        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: data)
        XCTAssertEqual(manifest.entryPoint, "plugin.js")
        XCTAssertEqual(manifest.exposedTools, ["echo.safe"])
        XCTAssertEqual(manifest.minimumIDEVersion, "1.2.0")
        XCTAssertEqual(Set(manifest.capabilities), [.readWorkspace, .networkAccess])
    }

    func testEngineManifestAdapterMapsCapabilitiesToExtensionContract() {
        let engineManifest = IDEPluginManifest(
            id: "plugin.contract.bridge",
            name: "Contract Bridge",
            version: "2.0.0",
            entryPoint: "plugin.js",
            capabilities: [.read, .web, .bash, .git],
            exposedTools: ["read", "web_search"]
        )

        let extensionManifest = EnginePluginManifestAdapter.toExtensionManifest(engineManifest)
        XCTAssertEqual(extensionManifest.entryPoint, "plugin.js")
        XCTAssertEqual(extensionManifest.exposedTools, ["read", "web_search"])
        XCTAssertEqual(
            Set(extensionManifest.capabilities),
            [.readWorkspace, .readOnlyTools, .networkAccess, .executeCommands]
        )
    }
}

private struct DangerousWritePlugin: IDEExtensionPlugin {
    let manifest = ExtensionManifest(
        id: "com.codigo.extensions.write-plugin",
        name: "Write Plugin",
        version: "1.0.0",
        entryPoint: "DangerousWritePlugin",
        capabilities: [.writeWorkspace],
        exposedTools: ["write.file"]
    )

    func onLoad(context: ExtensionRuntimeContext) async throws {
        _ = context
    }

    func onUnload(context: ExtensionRuntimeContext) async {
        _ = context
    }

    func handle(
        request: ExtensionToolRequest,
        context: ExtensionRuntimeContext
    ) async throws -> ExtensionToolResponse {
        _ = request
        _ = context
        return ExtensionToolResponse(output: "noop")
    }
}
