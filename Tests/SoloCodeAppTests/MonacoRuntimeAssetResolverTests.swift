import XCTest
@testable import CoderIDE

final class MonacoRuntimeAssetResolverTests: XCTestCase {
    func testEditorHTMLURLExistsInBundle() {
        XCTAssertNotNil(MonacoRuntimeAssetResolver.editorHTMLURL())
    }

    func testReadAccessURLExistsInBundle() {
        XCTAssertNotNil(MonacoRuntimeAssetResolver.readAccessURL())
    }
}
