import Foundation
import XCTest
@testable import CoderEngine

final class PluginRuntimeTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("plugin-runtime-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testLoadPluginAndComputeAllowedTools() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = root.appendingPathComponent("manifest.json")
        try """
        {
          "id": "plugin.safe.readonly",
          "name": "Safe Read Plugin",
          "version": "1.0.0",
          "entrypoint": "index.js",
          "capabilities": ["read", "web"],
          "allowedTools": ["read", "grep", "web_search"]
        }
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let runtime = PluginRuntime()
        let descriptor = try await runtime.loadPlugin(manifestURL: manifestURL)
        XCTAssertEqual(descriptor.manifest.id, "plugin.safe.readonly")
        let isLoaded = await runtime.isLoaded(id: "plugin.safe.readonly")
        XCTAssertTrue(isLoaded)

        let tools = await runtime.allowedTools(forPluginID: "plugin.safe.readonly")
        XCTAssertTrue(tools.contains("read"))
        XCTAssertTrue(tools.contains("grep"))
        XCTAssertTrue(tools.contains("web_search"))
        XCTAssertFalse(tools.contains("bash"))
    }

    func testLoadPluginSupportsUnifiedContractKeys() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = root.appendingPathComponent("manifest.json")
        try """
        {
          "id": "plugin.contract.unified",
          "name": "Unified Contract",
          "version": "1.0.0",
          "entryPoint": "index.js",
          "capabilities": ["workspace.read", "network.access"],
          "exposedTools": ["read", "web_search"],
          "minimumIDEVersion": "1.0.0"
        }
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let runtime = PluginRuntime(currentIDEVersion: "1.2.0")
        let descriptor = try await runtime.loadPlugin(manifestURL: manifestURL)

        XCTAssertEqual(descriptor.manifest.entryPoint, "index.js")
        XCTAssertEqual(descriptor.manifest.entrypoint, "index.js")
        XCTAssertEqual(descriptor.manifest.exposedTools, ["read", "web_search"])
        XCTAssertEqual(descriptor.manifest.allowedTools, ["read", "web_search"])
        XCTAssertEqual(descriptor.manifest.minimumIDEVersion, "1.0.0")
    }

    func testAllowedToolsDefaultsToCapabilityWhitelistWhenNotExplicitlySet() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = root.appendingPathComponent("manifest.json")
        try """
        {
          "id": "plugin.default.allowed-tools",
          "name": "Default Allowed Tools",
          "version": "1.0.0",
          "entrypoint": "index.js",
          "capabilities": ["read", "git"]
        }
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let runtime = PluginRuntime()
        _ = try await runtime.loadPlugin(manifestURL: manifestURL)

        let tools = await runtime.allowedTools(forPluginID: "plugin.default.allowed-tools")
        XCTAssertTrue(tools.contains("read"))
        XCTAssertTrue(tools.contains("git_diff"))
        XCTAssertFalse(tools.contains("bash"))
    }

    func testLoadPluginRejectsToolOutsideCapabilities() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = root.appendingPathComponent("manifest.json")
        try """
        {
          "id": "plugin.invalid",
          "name": "Invalid Plugin",
          "version": "1.0.0",
          "entrypoint": "index.js",
          "capabilities": ["read"],
          "allowedTools": ["bash"]
        }
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let runtime = PluginRuntime()
        do {
            _ = try await runtime.loadPlugin(manifestURL: manifestURL)
            XCTFail("Expected invalid manifest")
        } catch IDEPluginRuntimeError.invalidManifest(let detail) {
            XCTAssertTrue(detail.contains("bash"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadPluginRejectsMinimumIDEVersionAboveRuntimeVersion() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = root.appendingPathComponent("manifest.json")
        try """
        {
          "id": "plugin.version.gate",
          "name": "Version Gate",
          "version": "1.0.0",
          "entryPoint": "index.js",
          "capabilities": ["read"],
          "exposedTools": ["read"],
          "minimumIDEVersion": "2.0.0"
        }
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let runtime = PluginRuntime(currentIDEVersion: "1.4.0")
        do {
            _ = try await runtime.loadPlugin(manifestURL: manifestURL)
            XCTFail("Expected minimum IDE version rejection")
        } catch IDEPluginRuntimeError.minimumIDEVersionNotSatisfied(let required, let current) {
            XCTAssertEqual(required, "2.0.0")
            XCTAssertEqual(current, "1.4.0")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnloadPluginRemovesState() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = root.appendingPathComponent("manifest.json")
        try """
        {
          "id": "plugin.to.unload",
          "name": "Unload Plugin",
          "version": "1.0.0",
          "entrypoint": "index.js",
          "capabilities": ["read"]
        }
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let runtime = PluginRuntime()
        _ = try await runtime.loadPlugin(manifestURL: manifestURL)
        let loadedBeforeUnload = await runtime.isLoaded(id: "plugin.to.unload")
        XCTAssertTrue(loadedBeforeUnload)

        try await runtime.unloadPlugin(id: "plugin.to.unload")
        let loadedAfterUnload = await runtime.isLoaded(id: "plugin.to.unload")
        XCTAssertFalse(loadedAfterUnload)
        let toolsAfterUnload = await runtime.allowedTools(forPluginID: "plugin.to.unload")
        XCTAssertTrue(toolsAfterUnload.isEmpty)
    }

    func testUnloadPluginFailsWhenNotLoaded() async {
        let runtime = PluginRuntime()
        do {
            try await runtime.unloadPlugin(id: "plugin.missing")
            XCTFail("Expected plugin not loaded")
        } catch IDEPluginRuntimeError.pluginNotLoaded(let id) {
            XCTAssertEqual(id, "plugin.missing")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLifecycleHandlerReceivesLoadAndUnloadEvents() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = root.appendingPathComponent("manifest.json")
        try """
        {
          "id": "plugin.lifecycle.events",
          "name": "Lifecycle Events",
          "version": "1.0.0",
          "entryPoint": "index.js",
          "capabilities": ["read"],
          "exposedTools": ["read"]
        }
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let recorder = LifecycleRecorder()
        let runtime = PluginRuntime(currentIDEVersion: "1.0.0", lifecycleHandler: recorder)

        _ = try await runtime.loadPlugin(manifestURL: manifestURL)
        try await runtime.unloadPlugin(id: "plugin.lifecycle.events")
        let events = await recorder.events()

        XCTAssertEqual(events.loadedIDs, ["plugin.lifecycle.events"])
        XCTAssertEqual(events.unloadedIDs, ["plugin.lifecycle.events"])
    }
}

private actor LifecycleRecorder: PluginRuntimeLifecycleHandling {
    private var loadedIDs: [String] = []
    private var unloadedIDs: [String] = []

    func load(descriptor: IDEPluginDescriptor) async throws {
        loadedIDs.append(descriptor.manifest.id)
    }

    func unload(descriptor: IDEPluginDescriptor) async {
        unloadedIDs.append(descriptor.manifest.id)
    }

    func events() -> (loadedIDs: [String], unloadedIDs: [String]) {
        (loadedIDs, unloadedIDs)
    }
}
