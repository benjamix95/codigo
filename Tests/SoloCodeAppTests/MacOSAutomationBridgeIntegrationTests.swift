import XCTest
@testable import CoderIDE
@testable import CoderEngine

@MainActor
final class MacOSAutomationBridgeIntegrationTests: XCTestCase {
    func testMacOSAutomationServiceConformsToBridge() {
        let bridge: any MacOSAutomationBridge = MacOSAutomationService()
        XCTAssertNotNil(bridge)
    }

    func testModifierFlagsParseCommonAliases() {
        let flags = MacOSAutomationEventMapping.modifierFlags(
            from: ["command", "shift", "alt", "ctrl", "fn"]
        )
        XCTAssertTrue(flags.contains(.maskCommand))
        XCTAssertTrue(flags.contains(.maskShift))
        XCTAssertTrue(flags.contains(.maskAlternate))
        XCTAssertTrue(flags.contains(.maskControl))
        XCTAssertTrue(flags.contains(.maskSecondaryFn))
    }

    func testKeyCodeMappingSupportsCharactersAndNamedKeys() {
        XCTAssertEqual(MacOSAutomationEventMapping.keyCode(for: "d"), 2)
        XCTAssertEqual(MacOSAutomationEventMapping.keyCode(for: "p"), 35)
        XCTAssertEqual(MacOSAutomationEventMapping.keyCode(for: "return"), 36)
        XCTAssertEqual(MacOSAutomationEventMapping.keyCode(for: "escape"), 53)
        XCTAssertEqual(MacOSAutomationEventMapping.keyCode(for: "left"), 123)
        XCTAssertNil(MacOSAutomationEventMapping.keyCode(for: "unknown-key"))
    }

    func testResolveAppNameDefaultsToHostApp() {
        let service = MacOSAutomationService(hostAppName: "Solo Code", hostBundleID: "com.solocode.app")
        XCTAssertEqual(service.resolveAppName(appName: nil, bundleID: nil), "Solo Code")
    }
}
