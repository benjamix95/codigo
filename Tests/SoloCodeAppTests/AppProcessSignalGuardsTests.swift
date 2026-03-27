import XCTest
@testable import CoderIDE

final class AppProcessSignalGuardsTests: XCTestCase {
    func testIgnoredSignalSpecsCoverSighupAndSigpipe() {
        let specs = appIgnoredSignalSpecs()
        XCTAssertEqual(specs.map(\.name), ["SIGHUP", "SIGPIPE"])
        XCTAssertEqual(specs.map(\.number), [SIGHUP, SIGPIPE])
    }

    func testInstallAppProcessSignalGuardsIsIdempotent() {
        installAppProcessSignalGuardsIfNeeded()
        installAppProcessSignalGuardsIfNeeded()
    }
}
