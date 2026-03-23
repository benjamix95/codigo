import XCTest
@testable import CoderIDE

final class ExtensionXPCHostTests: XCTestCase {
    actor Probe {
        private(set) var timedOut = false

        func markTimeout() {
            timedOut = true
        }

        func value() -> Bool {
            timedOut
        }
    }

    func testExecuteRequestTimesOutAndRunsCleanup() async {
        let host = ExtensionXPCHost()
        let probe = Probe()

        do {
            let _: String = try await host.executeRequest(
                pluginId: "plugin.timeout",
                timeout: 0.01,
                timeoutError: {
                    XPCError.timeout(pluginId: "plugin.timeout", seconds: 0.01)
                },
                onTimeout: {
                    await probe.markTimeout()
                }
            ) { _ in
                // Never completes.
            }
            XCTFail("Expected timeout")
        } catch let error as XPCError {
            guard case .timeout(let pluginId, _) = error else {
                return XCTFail("Unexpected XPC error: \(error)")
            }
            XCTAssertEqual(pluginId, "plugin.timeout")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let timedOut = await probe.value()
        XCTAssertTrue(timedOut)
    }

    func testExecuteRequestIgnoresLateCompletions() async throws {
        let host = ExtensionXPCHost()

        let value: String = try await host.executeRequest(
            pluginId: "plugin.double",
            timeout: 1,
            timeoutError: {
                XPCError.timeout(pluginId: "plugin.double", seconds: 1)
            }
        ) { completion in
            completion(.success("first"))
            completion(.success("second"))
            completion(.failure(XPCError.invalidResponse))
        }

        XCTAssertEqual(value, "first")
    }

    func testActivateConnectionRollsBackWhenInitializerFails() async {
        let host = ExtensionXPCHost()
        let config = XPCPluginConfiguration(
            pluginId: "plugin.rollback",
            workspaceRoots: [],
            grantedCapabilities: [],
            timeout: 0.01
        )
        let connection = NSXPCConnection(serviceName: "com.solocode.tests.fake")

        do {
            try await host.activateConnection(
                pluginId: "plugin.rollback",
                connection: connection,
                configuration: config
            ) { _, _, _, _ in
                throw XPCError.invalidResponse
            }
            XCTFail("Expected initializer failure")
        } catch {
            // expected
        }

        let activeConnections = await host.activeConnections()
        let isAlive = await host.isAlive(pluginId: "plugin.rollback")
        XCTAssertTrue(activeConnections.isEmpty)
        XCTAssertFalse(isAlive)
    }
}
