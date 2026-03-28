import XCTest
@testable import CoderEngine

final class PerformanceAuditTests: XCTestCase {

    // MARK: - Helpers

    private func tempWorkspace(files: [String: String]) -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf-audit-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, content) in files {
            let fileURL = root.appendingPathComponent(name)
            try! FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try! content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return root
    }

    // MARK: - Bottleneck Tests

    func testPerfBottlenecksDetectsMainSync() {
        let workspace = tempWorkspace(files: [
            "Sources/Service.swift": """
            func doWork() {
                DispatchQueue.main.sync {
                    updateUI()
                }
            }
            """,
        ])
        let result = CodeReviewAuditService.runTool(
            named: ReviewAuditToolName.perfBottlenecks,
            scopeFiles: ["Sources/Service.swift"],
            workspacePath: workspace
        )
        XCTAssertFalse(result.findings.isEmpty, "Deve rilevare DispatchQueue.main.sync come bottleneck")
        XCTAssertTrue(result.findings.allSatisfy { $0.category == .performance })
        XCTAssertTrue(result.findings.contains { $0.severity == .critical })
    }

    func testPerfBottlenecksCleanFile() {
        let workspace = tempWorkspace(files: [
            "Sources/Clean.swift": """
            func doWork() {
                DispatchQueue.main.async {
                    updateUI()
                }
            }
            """,
        ])
        let result = CodeReviewAuditService.runTool(
            named: ReviewAuditToolName.perfBottlenecks,
            scopeFiles: ["Sources/Clean.swift"],
            workspacePath: workspace
        )
        XCTAssertTrue(result.findings.isEmpty, "File pulito non deve generare findings")
    }

    // MARK: - Memory Tests

    func testPerfMemoryDetectsStrongSelf() {
        let workspace = tempWorkspace(files: [
            "Sources/ViewModel.swift": """
            class ViewModel {
                func setup() {
                    service.onComplete { [strong self] in
                        self.update()
                    }
                }
            }
            """,
        ])
        let result = CodeReviewAuditService.runTool(
            named: ReviewAuditToolName.perfMemory,
            scopeFiles: ["Sources/ViewModel.swift"],
            workspacePath: workspace
        )
        XCTAssertFalse(result.findings.isEmpty, "Deve rilevare strong self come potenziale retain cycle")
        XCTAssertTrue(result.findings.allSatisfy { $0.category == .performance })
    }

    // MARK: - UI Responsiveness Tests

    func testPerfUIResponsivenessDetectsMainSync() {
        let workspace = tempWorkspace(files: [
            "Sources/View.swift": """
            struct MyView: View {
                var body: some View {
                    Text("hello")
                        .onAppear {
                            DispatchQueue.main.sync { loadData() }
                        }
                }
            }
            """,
        ])
        let result = CodeReviewAuditService.runTool(
            named: ReviewAuditToolName.perfUIResponsiveness,
            scopeFiles: ["Sources/View.swift"],
            workspacePath: workspace
        )
        XCTAssertFalse(result.findings.isEmpty, "Deve rilevare sync su main thread in codice UI")
    }

    // MARK: - Startup Tests

    func testPerfStartupDetectsLoad() {
        let workspace = tempWorkspace(files: [
            "Sources/AppDelegate.m": """
            @implementation AppDelegate
            + (void)load {
                [self setupEarly];
            }
            @end
            """,
        ])
        let result = CodeReviewAuditService.runTool(
            named: ReviewAuditToolName.perfStartup,
            scopeFiles: ["Sources/AppDelegate.m"],
            workspacePath: workspace
        )
        XCTAssertFalse(result.findings.isEmpty, "Deve rilevare +load come problema di startup")
    }

    // MARK: - Hot Paths Tests

    func testPerfHotPathsDetectsNestedLoops() {
        let workspace = tempWorkspace(files: [
            "Sources/Algorithm.swift": """
            func search(matrix: [[Int]], target: Int) -> Bool {
                for row in matrix {
                    for element in row {
                        if element == target { return true }
                    }
                }
                return false
            }
            """,
        ])
        let result = CodeReviewAuditService.runTool(
            named: ReviewAuditToolName.perfHotPaths,
            scopeFiles: ["Sources/Algorithm.swift"],
            workspacePath: workspace
        )
        XCTAssertFalse(result.findings.isEmpty, "Deve rilevare loop annidati come hot path")
    }

    // MARK: - Profile Tests

    func testPerformanceDeepProfileRunsAllPerfTools() {
        let workspace = tempWorkspace(files: [
            "Sources/App.swift": """
            func main() {
                DispatchQueue.main.sync { setup() }
                Thread.sleep(forTimeInterval: 1)
            }
            """,
        ])
        let results = CodeReviewAuditService.runProfile(
            named: .performanceDeep,
            scopeFiles: ["Sources/App.swift"],
            workspacePath: workspace
        )
        let toolNames = Set(results.map(\.toolName))
        XCTAssertTrue(toolNames.contains(ReviewAuditToolName.perfBottlenecks))
        XCTAssertTrue(toolNames.contains(ReviewAuditToolName.perfMemory))
        XCTAssertTrue(toolNames.contains(ReviewAuditToolName.perfUIResponsiveness))
        XCTAssertTrue(toolNames.contains(ReviewAuditToolName.perfStartup))
        XCTAssertTrue(toolNames.contains(ReviewAuditToolName.perfHotPaths))
    }

    // MARK: - Tool Names Registration

    func testPerformanceToolsAreInAllToolNames() {
        for tool in ReviewAuditToolName.performanceTools {
            XCTAssertTrue(
                ReviewAuditToolName.allToolNames.contains(tool),
                "\(tool) deve essere in allToolNames"
            )
        }
    }

    func testPerformanceToolsAreInAll() {
        for tool in ReviewAuditToolName.performanceTools {
            XCTAssertTrue(
                ReviewAuditToolName.all.contains(tool),
                "\(tool) deve essere in all"
            )
        }
    }
}
