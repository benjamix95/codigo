import Foundation
import XCTest
@testable import CoderEngine

final class CodebaseIndexIndexingBenchmarkSmokeTests: XCTestCase {
    func testIndexingBenchmarkSmoke() async throws {
        let env = ProcessInfo.processInfo.environment
        let config = loadBenchmarkConfig()
        let isFull = env["RUN_INDEX_BENCHMARK_SMOKE"] == "1"

        let measuredRuns = clampInt(env["INDEX_BENCHMARK_RUNS"] ?? config?.runsString, fallback: isFull ? 6 : 2, min: 1, max: 40)
        let warmupRuns = clampInt(env["INDEX_BENCHMARK_WARMUP"] ?? config?.warmupRunsString, fallback: isFull ? 2 : 0, min: 0, max: 10)
        let fileCount = clampInt(env["INDEX_BENCHMARK_FILES"] ?? config?.fileCountString, fallback: isFull ? 180 : 40, min: 10, max: 2_000)
        let phase = env["INDEX_BENCHMARK_PHASE"] ?? config?.phase ?? "adhoc"

        let workspace = try makeWorkspace(fileCount: fileCount)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let fullDurations = try await measureFullIndexing(
            workspace: workspace,
            warmupRuns: warmupRuns,
            measuredRuns: measuredRuns
        )

        let incrementalDurations = try await measureIncrementalIndexing(
            workspace: workspace,
            warmupRuns: warmupRuns,
            measuredRuns: measuredRuns
        )

        let fullStats = summarize(fullDurations)
        let incrementalStats = summarize(incrementalDurations)
        XCTAssertGreaterThan(fullStats.medianMs, 0)
        XCTAssertGreaterThan(incrementalStats.medianMs, 0)

        let payload: [String: Any] = [
            "phase": phase,
            "timestamp_utc": ISO8601DateFormatter().string(from: Date()),
            "runs": measuredRuns,
            "warmup_runs": warmupRuns,
            "dataset_files": fileCount,
            "full_median_ms": fullStats.medianMs,
            "full_p95_ms": fullStats.p95Ms,
            "full_max_ms": fullStats.maxMs,
            "incremental_median_ms": incrementalStats.medianMs,
            "incremental_p95_ms": incrementalStats.p95Ms,
            "incremental_max_ms": incrementalStats.maxMs,
        ]

        let encoded = try XCTUnwrap(encodeJSON(payload))
        let outputPath = env["INDEX_BENCHMARK_OUTPUT"] ?? config?.outputPath
        if let outputPath, !outputPath.isEmpty {
            try encoded.write(
                to: URL(fileURLWithPath: outputPath),
                atomically: true,
                encoding: .utf8
            )
        }
        print("INDEX_BENCHMARK_SMOKE_RESULT=\(encoded)")
        NSLog("INDEX_BENCHMARK_SMOKE_RESULT=%@", encoded)
    }

    private func measureFullIndexing(
        workspace: URL,
        warmupRuns: Int,
        measuredRuns: Int
    ) async throws -> [Int] {
        var durations: [Int] = []
        for run in 0..<(warmupRuns + measuredRuns) {
            let index = CodebaseIndex()
            let result = await index.indexWorkspace(paths: [workspace])
            if run >= warmupRuns {
                durations.append(result.durationMs)
            }
        }
        return durations
    }

    private func measureIncrementalIndexing(
        workspace: URL,
        warmupRuns: Int,
        measuredRuns: Int
    ) async throws -> [Int] {
        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])

        var durations: [Int] = []
        for run in 0..<(warmupRuns + measuredRuns) {
            let target = workspace.appendingPathComponent("Bench\(run % 20).swift")
            try """
            struct BenchMutated\(run) {
                let value = \(run)
                func probe() -> Int { value * 2 }
            }
            """.write(to: target, atomically: true, encoding: .utf8)

            let result = await index.incrementalUpdate()
            if run >= warmupRuns {
                durations.append(result.durationMs)
            }
        }
        return durations
    }

    private func makeWorkspace(fileCount: Int) throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("index-bench-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        for i in 0..<fileCount {
            try """
            struct Bench\(i) {
                let value = \(i)
                func flow\(i)() -> Int { value + \(i % 7) }
            }
            """.write(
                to: workspace.appendingPathComponent("Bench\(i).swift"),
                atomically: true,
                encoding: .utf8
            )
        }
        return workspace
    }

    private func summarize(_ values: [Int]) -> (medianMs: Int, p95Ms: Int, maxMs: Int) {
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]
        let p95 = percentile(sorted, p: 0.95)
        let maxMs = sorted.last ?? 0
        return (median, p95, maxMs)
    }

    private func percentile(_ sortedValues: [Int], p: Double) -> Int {
        guard !sortedValues.isEmpty else { return 0 }
        let clamped = min(max(p, 0), 1)
        let idx = Int((Double(sortedValues.count - 1) * clamped).rounded(.up))
        return sortedValues[idx]
    }

    private func clampInt(_ raw: String?, fallback: Int, min: Int, max: Int) -> Int {
        guard let raw, let parsed = Int(raw) else { return fallback }
        return Swift.max(min, Swift.min(max, parsed))
    }

    private func encodeJSON(_ payload: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func loadBenchmarkConfig() -> BenchmarkConfig? {
        let configURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("tmp/index-benchmark-config.json")
        guard let data = try? Data(contentsOf: configURL) else {
            return nil
        }
        return try? JSONDecoder().decode(BenchmarkConfig.self, from: data)
    }
}

private struct BenchmarkConfig: Decodable {
    let phase: String?
    let runs: Int?
    let warmupRuns: Int?
    let fileCount: Int?
    let outputPath: String?

    var runsString: String? { runs.map(String.init) }
    var warmupRunsString: String? { warmupRuns.map(String.init) }
    var fileCountString: String? { fileCount.map(String.init) }

    private enum CodingKeys: String, CodingKey {
        case phase
        case runs
        case warmupRuns = "warmup_runs"
        case fileCount = "files"
        case outputPath = "output_path"
    }
}
