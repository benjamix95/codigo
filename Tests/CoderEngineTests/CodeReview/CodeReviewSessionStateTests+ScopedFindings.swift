import XCTest
@testable import CoderEngine

extension CodeReviewSessionStateTests {
    func testReplaceOpenFindingsOnlyTouchesReviewedFiles() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift", "b.swift"])
        await state.start(scope: scope)
        await state.addFindings([
            CodeReviewFinding(id: "open-a", severity: .warning, category: .correctness, filePath: "a.swift", message: "a"),
            CodeReviewFinding(id: "open-b", severity: .warning, category: .correctness, filePath: "b.swift", message: "b"),
        ])

        await state.replaceOpenFindings(
            in: ["a.swift"],
            with: [
                CodeReviewFinding(
                    id: "replacement-a",
                    severity: .critical,
                    category: .security,
                    filePath: "a.swift",
                    message: "new a"
                )
            ]
        )

        let snap = await state.snapshot()
        XCTAssertEqual(
            snap.openFindings.map(\.id).sorted(),
            ["open-b", "replacement-a"]
        )
    }

    func testMarkOpenFindingsAsFixAppliedOnlyTouchesRequestedFiles() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift", "b.swift"])
        await state.start(scope: scope)
        await state.addFindings([
            CodeReviewFinding(id: "open-a", severity: .warning, category: .correctness, filePath: "a.swift", message: "a"),
            CodeReviewFinding(id: "open-b", severity: .warning, category: .correctness, filePath: "b.swift", message: "b"),
        ])

        await state.markOpenFindingsAsFixApplied(in: ["a.swift"])

        let snap = await state.snapshot()
        XCTAssertEqual(
            snap.findings.first(where: { $0.id == "open-a" })?.status,
            .fixApplied
        )
        XCTAssertEqual(
            snap.findings.first(where: { $0.id == "open-b" })?.status,
            .open
        )
    }

    func testMutationSequenceIncreasesAcrossStateChanges() async {
        let state = CodeReviewSessionState()
        let initial = await state.snapshot()
        await state.start(scope: ReviewSessionScope(type: .uncommitted, files: ["a.swift"]))
        let started = await state.snapshot()
        await state.addFinding(CodeReviewFinding(
            severity: .warning,
            category: .correctness,
            filePath: "a.swift",
            message: "test"
        ))
        let updated = await state.snapshot()

        XCTAssertLessThan(initial.mutationSequence, started.mutationSequence)
        XCTAssertLessThan(started.mutationSequence, updated.mutationSequence)
    }
}
