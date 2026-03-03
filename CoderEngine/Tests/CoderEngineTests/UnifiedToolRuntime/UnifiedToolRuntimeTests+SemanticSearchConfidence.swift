import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    func testSemanticSearchUsesDefaultMinConfidence045() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try """
        struct ConfidenceProbe {
            func authFlow() { print("auth confidence probe") }
        }
        """.write(to: tmp.appendingPathComponent("ConfidenceProbe.swift"), atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "auth confidence probe"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        let diagnostics = completed?["diagnostics"] ?? ""

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(
            diagnostics.contains("min_conf=0.45"),
            "Expected default confidence in diagnostics, got: \(diagnostics)"
        )
    }

    func testSemanticSearchMinConfidenceNaNFallsBackToDefault() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "struct NaNConfidence { func search() {} }".write(
            to: tmp.appendingPathComponent("NaNConfidence.swift"),
            atomically: true,
            encoding: .utf8
        )

        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "NaNConfidence", "min_confidence": "NaN"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        let diagnostics = completed?["diagnostics"] ?? ""
        XCTAssertTrue(diagnostics.contains("min_conf=0.45"))
    }

    func testBuildGrepPatternsDeduplicates() async {
        let runtime = UnifiedToolRuntime()
        let patterns = await runtime.buildGrepPatterns(queryTokens: ["auth", "auth"])
        XCTAssertEqual(Set(patterns).count, patterns.count)
    }

    func testBuildGrepPatternsIncludesTwoCharacterTokens() async {
        let runtime = UnifiedToolRuntime()
        let patterns = await runtime.buildGrepPatterns(queryTokens: ["ui"])
        XCTAssertTrue(patterns.contains("ui"))
    }
}
