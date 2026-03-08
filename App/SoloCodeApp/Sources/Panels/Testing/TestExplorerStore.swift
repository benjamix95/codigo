import SwiftUI

// MARK: - Test Explorer Store

/// Store per la gestione dello stato del Test Explorer Panel.
@MainActor
final class TestExplorerStore: ObservableObject {
    @Published var targets: [TestTarget] = []
    @Published var isDiscovering: Bool = false
    @Published var isRunning: Bool = false
    @Published var lastRunResult: TestRunResult?
    @Published var coverageReport: CoverageReport?
    @Published var selectedTestId: String?
    @Published var filterText: String = ""
    @Published var showOnlyFailed: Bool = false

    private let testRunner = TestRunnerService()
    private let coverageParser = CoverageParser()

    var filteredTargets: [TestTarget] {
        let baseTargets = targets
        guard !filterText.isEmpty || showOnlyFailed else { return baseTargets }

        return baseTargets.compactMap { target in
            let filteredSuites = target.suites.compactMap { suite -> TestSuite? in
                let filteredTests = suite.tests.filter { test in
                    let matchesFilter = filterText.isEmpty
                        || test.name.localizedCaseInsensitiveContains(filterText)
                        || test.suiteName.localizedCaseInsensitiveContains(filterText)
                    let matchesFailed = !showOnlyFailed || test.status == .failed
                    return matchesFilter && matchesFailed
                }
                guard !filteredTests.isEmpty else { return nil }
                return TestSuite(name: suite.name, targetName: suite.targetName, tests: filteredTests)
            }
            guard !filteredSuites.isEmpty else { return nil }
            return TestTarget(name: target.name, suites: filteredSuites)
        }
    }

    var totalTests: Int { targets.reduce(0) { $0 + $1.totalCount } }
    var passedTests: Int { targets.reduce(0) { $0 + $1.passedCount } }
    var failedTests: Int { targets.reduce(0) { $0 + $1.failedCount } }

    // MARK: - Actions

    func discoverTests(projectPath: String) {
        isDiscovering = true
        Task { [weak self] in
            guard let self else { return }
            let discovered = await self.testRunner.discoverTests(projectPath: projectPath)
            await MainActor.run {
                self.targets = discovered
                self.isDiscovering = false
            }
        }
    }

    func runAllTests(projectPath: String) {
        guard !isRunning else { return }
        isRunning = true
        Task { [weak self] in
            guard let self else { return }
            let result = await self.testRunner.runAllTests(projectPath: projectPath)
            await MainActor.run {
                self.lastRunResult = result
                self.updateTargetsFromResult(result)
                self.isRunning = false
            }
        }
    }

    func runSingleTest(testId: String, projectPath: String) {
        guard !isRunning else { return }
        isRunning = true
        Task { [weak self] in
            guard let self else { return }
            let result = await self.testRunner.runSingleTest(testId: testId, projectPath: projectPath)
            await MainActor.run {
                self.lastRunResult = result
                self.updateTargetsFromResult(result)
                self.isRunning = false
            }
        }
    }

    func runTestSuite(suiteName: String, projectPath: String) {
        guard !isRunning else { return }
        isRunning = true
        Task { [weak self] in
            guard let self else { return }
            let result = await self.testRunner.runTestSuite(suiteName: suiteName, projectPath: projectPath)
            await MainActor.run {
                self.lastRunResult = result
                self.updateTargetsFromResult(result)
                self.isRunning = false
            }
        }
    }

    func generateCoverage(projectPath: String) {
        isRunning = true
        Task { [weak self] in
            guard let self else { return }
            let report = await self.coverageParser.generateCoverage(projectPath: projectPath)
            await MainActor.run {
                self.coverageReport = report
                self.isRunning = false
            }
        }
    }

    // MARK: - Private

    private func updateTargetsFromResult(_ result: TestRunResult) {
        guard !result.targets.isEmpty else { return }
        targets = result.targets
    }
}
