import XCTest
@testable import CoderIDE
@testable import CoderEngine

final class BugHunterRunIdentityResolverTests: XCTestCase {
    func testCanonicalPrimaryCommitPrefersExplicitCommitForCommitWindow() {
        let resolved = BugHunterRunIdentityResolver.canonicalPrimaryCommit(
            sourceKind: .commitWindow,
            payloadPrimaryCommit: "abc123",
            resolvedPrimaryCommit: "HEAD^..HEAD"
        )

        XCTAssertEqual(resolved, "abc123")
    }

    func testCanonicalPrimaryCommitIgnoresAgainstRefForBranchWindow() {
        let resolved = BugHunterRunIdentityResolver.canonicalPrimaryCommit(
            sourceKind: .branchWindow,
            payloadPrimaryCommit: "abc123",
            resolvedPrimaryCommit: "abc123"
        )

        XCTAssertNil(resolved)
    }
}
