import XCTest
@testable import CoderIDE

@MainActor
final class EditorDiagnosticsStoreTests: XCTestCase {
    func testReplaceBuiltInDiagnosticsComputesSummary() {
        let store = EditorDiagnosticsStore()
        let payload = MonacoMarkerPayload(
            path: "/tmp/main.swift",
            markers: [
                .init(
                    message: "Unexpected token",
                    severity: 8,
                    source: "monaco",
                    startLineNumber: 4,
                    startColumn: 2,
                    endLineNumber: 4,
                    endColumn: 8
                ),
                .init(
                    message: "Unused variable",
                    severity: 4,
                    source: "monaco",
                    startLineNumber: 6,
                    startColumn: 1,
                    endLineNumber: 6,
                    endColumn: 5
                )
            ]
        )

        store.replaceBuiltInDiagnostics(payload)
        let summary = store.summary(for: "/tmp/main.swift")

        XCTAssertEqual(summary.errors, 1)
        XCTAssertEqual(summary.warnings, 1)
        XCTAssertEqual(store.diagnostics(for: "/tmp/main.swift").count, 2)
    }
}
