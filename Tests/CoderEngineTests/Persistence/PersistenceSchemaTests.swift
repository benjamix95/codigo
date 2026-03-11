import XCTest
@testable import CoderEngine

final class PersistenceSchemaTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        PersistenceTestSupport.resetPersistenceEnvironment()
        PersistenceTestSupport.enablePersistenceForTests()
    }

    override func tearDownWithError() throws {
        PersistenceTestSupport.resetPersistenceEnvironment()
        try super.tearDownWithError()
    }

    func testBootstrapCreatesCoreTablesAndIndexes() throws {
        let service = ManagedPostgresService()
        let store = PostgresPersistenceStore(postgresService: service)
        _ = try PersistenceBootstrapService(store: store).bootstrapIfNeeded()

        let tables = try service.runPSQL(
            databaseName: ManagedPostgresConfiguration.default.databaseName,
            sql: """
            SELECT tablename
            FROM pg_tables
            WHERE schemaname = 'public'
              AND tablename IN ('pipeline_runs', 'findings', 'review_sessions', 'bug_hunter_runs', 'plans', 'debug_runs', 'panel_projection')
            ORDER BY tablename;
            """
        )
        let indexes = try service.runPSQL(
            databaseName: ManagedPostgresConfiguration.default.databaseName,
            sql: """
            SELECT indexname
            FROM pg_indexes
            WHERE schemaname = 'public'
              AND indexname IN ('idx_findings_fingerprint', 'idx_findings_domain', 'idx_findings_status', 'idx_findings_file', 'idx_pipeline_events_run', 'idx_pipeline_events_entity', 'idx_pipeline_events_type', 'idx_command_log_command_id', 'idx_command_log_entity_fingerprint')
            ORDER BY indexname;
            """
        )

        XCTAssertEqual(
            Set(tables.split(separator: "\n").map(String.init)),
            ["bug_hunter_runs", "debug_runs", "findings", "panel_projection", "pipeline_runs", "plans", "review_sessions"]
        )
        XCTAssertEqual(
            Set(indexes.split(separator: "\n").map(String.init)),
            [
                "idx_command_log_command_id",
                "idx_command_log_entity_fingerprint",
                "idx_findings_domain",
                "idx_findings_file",
                "idx_findings_fingerprint",
                "idx_findings_status",
                "idx_pipeline_events_entity",
                "idx_pipeline_events_run",
                "idx_pipeline_events_type",
            ]
        )
    }

    func testMutableTablesExposeVersionColumns() throws {
        let service = ManagedPostgresService()
        let store = PostgresPersistenceStore(postgresService: service)
        _ = try PersistenceBootstrapService(store: store).bootstrapIfNeeded()

        let output = try service.runPSQL(
            databaseName: ManagedPostgresConfiguration.default.databaseName,
            sql: """
            SELECT table_name || ':' || column_default
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND column_name = 'version'
              AND table_name IN ('workspaces', 'conversations', 'review_sessions', 'bug_hunter_runs', 'pipeline_runs', 'findings', 'plans', 'debug_runs')
            ORDER BY table_name;
            """
        )

        let rows = output.split(separator: "\n").map(String.init)
        XCTAssertEqual(rows.count, 8)
        XCTAssertTrue(rows.allSatisfy { $0.contains("nextval") == false && $0.contains("1") })
    }

    func testDefaultConfigurationUsesTemporaryRootDuringPersistenceTests() {
        let configuration = ManagedPostgresConfiguration.default

        XCTAssertEqual(
            configuration.rootDirectory.path,
            PersistenceTestSupport.temporaryRootDirectory().path
        )
        XCTAssertEqual(configuration.port, PersistenceTestSupport.temporaryPort())
        XCTAssertFalse(
            configuration.rootDirectory.path.contains("Library/Application Support/CoderIDE/postgres")
        )
    }
}
