import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    func testSearchHealthCheckReportsVectorAndTrigramStatus() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "search_health_check",
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertNotNil(completed?["vector_enabled"])
        XCTAssertNotNil(completed?["vector_db_available"])
        XCTAssertNotNil(completed?["embedding_row_count"])
        XCTAssertNotNil(completed?["embedding_file_count"])
        XCTAssertNotNil(completed?["trigram_enabled"])
        XCTAssertNotNil(completed?["embedding_backend"])
        XCTAssertNotNil(completed?["postgres_port"])
        XCTAssertNotNil(completed?["postgres_root"])
        XCTAssertTrue(output.contains("vector_enabled"))
        XCTAssertTrue(output.contains("vector_db_available"))
        XCTAssertTrue(output.contains("embedding_row_count"))
        XCTAssertTrue(output.contains("embedding_file_count"))
        XCTAssertTrue(output.contains("trigram_enabled"))
        XCTAssertTrue(output.contains("embedding_backend"))
        XCTAssertTrue(output.contains("postgres_port"))
        XCTAssertTrue(output.contains("postgres_root"))
    }
}
