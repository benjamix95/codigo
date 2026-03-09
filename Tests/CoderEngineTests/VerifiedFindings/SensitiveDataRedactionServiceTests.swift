import XCTest
@testable import CoderEngine

final class SensitiveDataRedactionServiceTests: XCTestCase {
    func testRedactsCommonSecrets() {
        let input = "token=secret-value Authorization: Bearer abc123 ghp_12345678901234567890"
        let result = SensitiveDataRedactionService.redact(input)
        XCTAssertTrue(result.wasRedacted)
        XCTAssertFalse(result.value.contains("secret-value"))
        XCTAssertFalse(result.value.contains("abc123"))
        XCTAssertFalse(result.value.contains("ghp_12345678901234567890"))
    }
}
