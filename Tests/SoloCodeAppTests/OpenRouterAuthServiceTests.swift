import XCTest
@testable import CoderIDE

final class OpenRouterAuthServiceTests: XCTestCase {
    func testGenerateCodeVerifierIsBase64URLEncoded() {
        let verifier = OpenRouterAuthService.generateCodeVerifier()

        XCTAssertFalse(verifier.isEmpty)
        XCTAssertFalse(verifier.contains("+"), "Should not contain + (base64url)")
        XCTAssertFalse(verifier.contains("/"), "Should not contain / (base64url)")
        XCTAssertFalse(verifier.contains("="), "Should not contain = padding")
    }

    func testGenerateCodeVerifierIsDeterministicLength() {
        let verifier = OpenRouterAuthService.generateCodeVerifier()

        // 32 random bytes → base64 = 44 chars - padding ≈ 43 chars
        XCTAssertGreaterThanOrEqual(verifier.count, 40)
        XCTAssertLessThanOrEqual(verifier.count, 44)
    }

    func testGenerateCodeVerifierProducesUniqueValues() {
        let v1 = OpenRouterAuthService.generateCodeVerifier()
        let v2 = OpenRouterAuthService.generateCodeVerifier()

        XCTAssertNotEqual(v1, v2, "Two verifiers should be unique")
    }

    func testGenerateCodeChallengeIsBase64URLEncoded() {
        let verifier = OpenRouterAuthService.generateCodeVerifier()
        let challenge = OpenRouterAuthService.generateCodeChallenge(from: verifier)

        XCTAssertNotNil(challenge)
        XCTAssertFalse(challenge!.contains("+"))
        XCTAssertFalse(challenge!.contains("/"))
        XCTAssertFalse(challenge!.contains("="))
    }

    func testGenerateCodeChallengeIsDeterministic() {
        let verifier = "test-verifier-string"
        let c1 = OpenRouterAuthService.generateCodeChallenge(from: verifier)
        let c2 = OpenRouterAuthService.generateCodeChallenge(from: verifier)

        XCTAssertEqual(c1, c2, "Same verifier should produce same challenge")
    }

    func testGenerateCodeChallengeDiffersForDifferentVerifiers() {
        let c1 = OpenRouterAuthService.generateCodeChallenge(from: "verifier-a")
        let c2 = OpenRouterAuthService.generateCodeChallenge(from: "verifier-b")

        XCTAssertNotEqual(c1, c2)
    }

    func testGenerateCodeChallengeIsSHA256Length() {
        let verifier = OpenRouterAuthService.generateCodeVerifier()
        let challenge = OpenRouterAuthService.generateCodeChallenge(from: verifier)

        XCTAssertNotNil(challenge)
        // SHA256 = 32 bytes → base64url = 43 chars
        XCTAssertEqual(challenge!.count, 43)
    }
}
