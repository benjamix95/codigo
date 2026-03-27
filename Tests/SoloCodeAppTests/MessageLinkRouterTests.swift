import XCTest
@testable import CoderIDE

final class MessageLinkRouterTests: XCTestCase {
    func testDispositionRoutesFileURLsInternally() {
        let url = URL(fileURLWithPath: "/tmp/build.log")

        XCTAssertEqual(MessageLinkRouter.disposition(for: url), .file("/tmp/build.log"))
    }

    func testDispositionAllowsXcodeLogDeepLinks() {
        let url = try! XCTUnwrap(URL(string: "x-xcode-log://5D42E586-3955-4EE6-B387-CB5E536E44CB"))

        XCTAssertEqual(MessageLinkRouter.disposition(for: url), .external(url))
    }

    func testDispositionRejectsUnsupportedSchemes() {
        let url = try! XCTUnwrap(URL(string: "javascript:alert(1)"))

        XCTAssertEqual(MessageLinkRouter.disposition(for: url), .ignored)
    }
}
