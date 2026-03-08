import SwiftUI

// MARK: - Test Explorer Panel

/// Pannello SwiftUI per il Test Explorer con tree view per target/suite/test.
struct TestExplorerPanel: View {
    @ObservedObject var store: TestExplorerStore
    let projectPath: String

    var body: some View {
        VStack(spacing: 0) {
            testToolbar
            Divider()
            if store.isDiscovering {
                progressView("Ricerca test in corso...")
            } else if store.filteredTargets.isEmpty {
                emptyState
            } else {
                testTreeView
            }
            if let result = store.lastRunResult {
                Divider()
                resultSummary(result)
            }
            if let coverage = store.coverageReport, coverage.isSuccess {
                Divider()
                coverageSummary(coverage)
            }
        }
    }

    // MARK: - Toolbar

    private var testToolbar: some View {
        HStack(spacing: 8) {
            Button(action: { store.discoverTests(projectPath: projectPath) }) {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .help("Riscopri test")

            Button(action: { store.runAllTests(projectPath: projectPath) }) {
                Image(systemName: "play.fill")
            }
            .disabled(store.isRunning)
            .help("Esegui tutti i test")

            Button(action: { store.generateCoverage(projectPath: projectPath) }) {
                Image(systemName: "chart.bar.fill")
            }
            .disabled(store.isRunning)
            .help("Genera code coverage")

            Spacer()

            Toggle(isOn: $store.showOnlyFailed) {
                Image(systemName: "xmark.circle")
            }
            .toggleStyle(.button)
            .help("Mostra solo falliti")

            TextField("Filtra...", text: $store.filterText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 150)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Tree View

    private var testTreeView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(store.filteredTargets) { target in
                    targetRow(target)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func targetRow(_ target: TestTarget) -> some View {
        DisclosureGroup {
            ForEach(target.suites) { suite in
                suiteRow(suite)
            }
        } label: {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.blue)
                Text(target.name)
                    .font(.system(.body, design: .monospaced))
                Spacer()
                testCountBadge(passed: target.passedCount, failed: target.failedCount)
            }
        }
    }

    private func suiteRow(_ suite: TestSuite) -> some View {
        DisclosureGroup {
            ForEach(suite.tests) { test in
                testCaseRow(test)
            }
        } label: {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.secondary)
                Text(suite.name)
                    .font(.system(.callout, design: .monospaced))
                Spacer()
                testCountBadge(passed: suite.passedCount, failed: suite.failedCount)
            }
        }
        .padding(.leading, 8)
    }

    private func testCaseRow(_ test: TestCase) -> some View {
        HStack {
            statusIcon(for: test.status)
            Text(test.name)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(test.status == .failed ? .red : .primary)
            Spacer()
            if let duration = test.duration {
                Text(String(format: "%.2fs", duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button(action: { store.runSingleTest(testId: test.id, projectPath: projectPath) }) {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.plain)
            .disabled(store.isRunning)
        }
        .padding(.leading, 16)
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func statusIcon(for status: TestStatus) -> some View {
        switch status {
        case .passed:
            return Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            return Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        case .running:
            return Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(.blue)
        case .skipped:
            return Image(systemName: "minus.circle").foregroundColor(.secondary)
        case .pending:
            return Image(systemName: "circle").foregroundColor(.secondary)
        }
    }

    private func testCountBadge(passed: Int, failed: Int) -> some View {
        HStack(spacing: 4) {
            if passed > 0 {
                Text("\(passed)").font(.caption2).foregroundColor(.green)
            }
            if failed > 0 {
                Text("\(failed)").font(.caption2).foregroundColor(.red)
            }
        }
    }

    private func resultSummary(_ result: TestRunResult) -> some View {
        HStack {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.isSuccess ? .green : .red)
            Text("\(result.passedCount)/\(result.totalCount) passati")
                .font(.caption)
            Spacer()
            Text(String(format: "%.1fs", result.totalDuration))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func coverageSummary(_ coverage: CoverageReport) -> some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(.blue)
            Text(String(format: "Coverage: %.1f%%", coverage.overallPercentage))
                .font(.caption)
            Text("(\(coverage.totalCoveredLines)/\(coverage.totalExecutableLines) righe)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "testtube.2")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Nessun test trovato")
                .font(.headline)
            Text("Clicca il bottone di refresh per scoprire i test.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progressView(_ text: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(text).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
