import XCTest
@testable import CoderEngine

extension CodeReviewMultiSwarmProviderTests {
    // MARK: - parseAgainstRef

    func testParseAgainstRef_withValidRef() {
        let (clean, ref) = CodeReviewMultiSwarmProvider.parseAgainstRef(from: "[AGAINST:abc123] Review my code")
        XCTAssertEqual(ref, "abc123")
        XCTAssertEqual(clean, "Review my code")
    }

    func testParseAgainstRef_withRefOnly() {
        let (clean, ref) = CodeReviewMultiSwarmProvider.parseAgainstRef(from: "[AGAINST:main]")
        XCTAssertEqual(ref, "main")
        XCTAssertEqual(clean, "Review all changes")
    }

    func testParseAgainstRef_withoutRef() {
        let (clean, ref) = CodeReviewMultiSwarmProvider.parseAgainstRef(from: "Just review everything")
        XCTAssertNil(ref)
        XCTAssertEqual(clean, "Just review everything")
    }

    func testParseAgainstRef_trimsWhitespace() {
        let (_, ref) = CodeReviewMultiSwarmProvider.parseAgainstRef(from: "[AGAINST:  HEAD~3  ] rest")
        XCTAssertEqual(ref, "HEAD~3")
    }

    func testParseAgainstRef_notAtStart() {
        let (clean, ref) = CodeReviewMultiSwarmProvider.parseAgainstRef(from: "prefix [AGAINST:abc] rest")
        XCTAssertEqual(ref, "abc")
        XCTAssertFalse(clean.contains("[AGAINST:abc]"))
        XCTAssertTrue(clean.contains("prefix"))
        XCTAssertTrue(clean.contains("rest"))
    }

    func testParseAgainstRef_ignoresConversationContextSection() {
        let prompt = """
        Review this diff.
        ## Conversation context (recent)
        user: [AGAINST:old-ref] previous run
        """
        let (clean, ref) = CodeReviewMultiSwarmProvider.parseAgainstRef(from: prompt)
        XCTAssertNil(ref)
        XCTAssertEqual(clean, prompt)
    }

    // MARK: - parseReviewScope

    func testParseReviewScope_withStagedMarker() {
        let (clean, scope) = CodeReviewMultiSwarmProvider.parseReviewScope(
            from: "[REVIEW_SCOPE:staged] Review staged changes only."
        )
        XCTAssertEqual(scope, .staged)
        XCTAssertFalse(clean.contains("[REVIEW_SCOPE:staged]"))
        XCTAssertEqual(clean, "Review staged changes only.")
    }

    func testParseReviewScope_ignoresConversationContextMarker() {
        let prompt = """
        Run review.
        ## Conversation context (recent)
        user: [REVIEW_SCOPE:staged] old command
        """
        let (clean, scope) = CodeReviewMultiSwarmProvider.parseReviewScope(from: prompt)
        XCTAssertNil(scope)
        XCTAssertEqual(clean, prompt)
    }

    func testParseReviewScope_withWorkspaceMarker() {
        let (clean, scope) = CodeReviewMultiSwarmProvider.parseReviewScope(
            from: "[REVIEW_SCOPE:workspace] Review the repository architecture."
        )
        XCTAssertEqual(scope, .workspace)
        XCTAssertFalse(clean.contains("[REVIEW_SCOPE:workspace]"))
        XCTAssertEqual(clean, "Review the repository architecture.")
    }

    func testInferReviewScope_detectsStagedLanguage() {
        let scope = CodeReviewMultiSwarmProvider.inferReviewScope(
            from: "Review ONLY staged changes and ignore unstaged."
        )
        XCTAssertEqual(scope, .staged)
    }

    func testInferReviewScope_detectsSlashCommand() {
        let scope = CodeReviewMultiSwarmProvider.inferReviewScope(from: "/review-staged")
        XCTAssertEqual(scope, .staged)
    }

    func testInferReviewScope_detectsWorkspaceLanguage() {
        let scope = CodeReviewMultiSwarmProvider.inferReviewScope(
            from: "Please review the workspace architecture."
        )
        XCTAssertEqual(scope, .workspace)
    }

    // MARK: - isValidAgainstRefFormat

    func testIsValidAgainstRefFormat_acceptsCommonRevisionExpressions() {
        XCTAssertTrue(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("HEAD~1"))
        XCTAssertTrue(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("main..feature"))
        XCTAssertTrue(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("abc123def"))
        XCTAssertTrue(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("feature^"))
    }

    func testIsValidAgainstRefFormat_rejectsUnsafeOrInvalidInput() {
        XCTAssertFalse(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat(""))
        XCTAssertFalse(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat(" "))
        XCTAssertFalse(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("--cached"))
        XCTAssertFalse(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("ref with space"))
        XCTAssertFalse(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("ref:path"))
        XCTAssertFalse(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("ref@{0}"))
    }

    func testNormalizedAgainstRefRevisionExpandsSingleRefToMergeBaseRange() {
        XCTAssertEqual(
            CodeReviewMultiSwarmProvider.normalizedAgainstRefRevision("main"),
            "main...HEAD"
        )
    }

    func testNormalizedAgainstRefInputExpandsSingleCommitOIDToCommitRange() {
        XCTAssertEqual(
            CodeReviewMultiSwarmProvider.normalizedAgainstRefInput("1e72c30"),
            "1e72c30^..1e72c30"
        )
    }

    func testNormalizedAgainstRefRevisionPreservesSingleCommitRangeExpansion() {
        XCTAssertEqual(
            CodeReviewMultiSwarmProvider.normalizedAgainstRefRevision("1e72c30"),
            "1e72c30^..1e72c30"
        )
    }

    func testNormalizedAgainstRefRevisionPreservesExplicitRange() {
        XCTAssertEqual(
            CodeReviewMultiSwarmProvider.normalizedAgainstRefRevision("main..feature"),
            "main..feature"
        )
    }
}
