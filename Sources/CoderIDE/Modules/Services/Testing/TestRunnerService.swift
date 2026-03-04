import Foundation

// MARK: - Test Runner Service

/// Servizio per esecuzione test Swift Package Manager.
/// Supporta discovery, esecuzione singola/bulk, e streaming risultati.
actor TestRunnerService {
    private let discovery: TestDiscovery
    private var cachedTargets: [TestTarget] = []
    private var isRunning: Bool = false

    init() {
        self.discovery = TestDiscovery()
    }

    // MARK: - Discovery

    /// Scopre tutti i test disponibili nel progetto.
    func discoverTests(projectPath: String) async -> [TestTarget] {
        let targets = await discovery.discoverTests(projectPath: projectPath)
        cachedTargets = targets
        return targets
    }

    /// Restituisce i test dalla cache (senza ri-scoperta).
    func cachedTestTargets() -> [TestTarget] {
        cachedTargets
    }

    // MARK: - Execution

    /// Esegue tutti i test.
    func runAllTests(projectPath: String) async -> TestRunResult {
        guard !isRunning else {
            return .failure(error: "Un'esecuzione test è già in corso.")
        }
        isRunning = true
        defer { isRunning = false }

        let start = Date()
        let result = await executeSwiftTest(
            arguments: ["test", "--package-path", projectPath],
            projectPath: projectPath
        )
        let duration = Date().timeIntervalSince(start)

        return parseTestOutput(result: result, duration: duration)
    }

    /// Esegue un singolo test per nome qualificato.
    func runSingleTest(
        testId: String,
        projectPath: String
    ) async -> TestRunResult {
        guard !isRunning else {
            return .failure(error: "Un'esecuzione test è già in corso.")
        }
        isRunning = true
        defer { isRunning = false }

        let start = Date()
        let result = await executeSwiftTest(
            arguments: ["test", "--package-path", projectPath, "--filter", testId],
            projectPath: projectPath
        )
        let duration = Date().timeIntervalSince(start)

        return parseTestOutput(result: result, duration: duration)
    }

    /// Esegue tutti i test in una suite specifica.
    func runTestSuite(
        suiteName: String,
        projectPath: String
    ) async -> TestRunResult {
        guard !isRunning else {
            return .failure(error: "Un'esecuzione test è già in corso.")
        }
        isRunning = true
        defer { isRunning = false }

        let start = Date()
        let result = await executeSwiftTest(
            arguments: ["test", "--package-path", projectPath, "--filter", suiteName],
            projectPath: projectPath
        )
        let duration = Date().timeIntervalSince(start)

        return parseTestOutput(result: result, duration: duration)
    }

    /// Verifica se un'esecuzione è in corso.
    func isTestRunning() -> Bool {
        isRunning
    }

    // MARK: - Private

    private func executeSwiftTest(
        arguments: [String],
        projectPath: String
    ) async -> TestProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: TestProcessResult(
                    exitCode: 1, stdout: "", stderr: error.localizedDescription
                ))
                return
            }

            process.terminationHandler = { proc in
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: TestProcessResult(
                    exitCode: proc.terminationStatus, stdout: out, stderr: err
                ))
            }
        }
    }

    private func parseTestOutput(result: TestProcessResult, duration: TimeInterval) -> TestRunResult {
        let combined = result.stdout + "\n" + result.stderr
        let targets = parseTestResults(from: combined)

        if result.exitCode != 0 && targets.isEmpty {
            return TestRunResult(
                targets: [],
                totalDuration: duration,
                exitCode: result.exitCode,
                error: result.stderr.isEmpty ? "Test falliti." : result.stderr
            )
        }

        return TestRunResult(
            targets: targets,
            totalDuration: duration,
            exitCode: result.exitCode,
            error: nil
        )
    }

    private func parseTestResults(from output: String) -> [TestTarget] {
        var targetMap: [String: [String: [TestCase]]] = [:]

        // Pattern: Test Case '-[TargetName.SuiteName testName]' passed/failed (N.NNN seconds)
        let pattern = #"Test Case '-\[(\w+)\.(\w+) (\w+)\]' (passed|failed) \(([\d.]+) seconds\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsOutput = output as NSString
        let matches = regex.matches(in: output, range: NSRange(location: 0, length: nsOutput.length))

        for match in matches {
            guard match.numberOfRanges == 6 else { continue }
            let target = nsOutput.substring(with: match.range(at: 1))
            let suite = nsOutput.substring(with: match.range(at: 2))
            let name = nsOutput.substring(with: match.range(at: 3))
            let statusStr = nsOutput.substring(with: match.range(at: 4))
            let durationStr = nsOutput.substring(with: match.range(at: 5))

            var testCase = TestCase(name: name, suiteName: suite, targetName: target)
            testCase.status = statusStr == "passed" ? .passed : .failed
            testCase.duration = Double(durationStr)

            targetMap[target, default: [:]][suite, default: []].append(testCase)
        }

        return targetMap.map { targetName, suites in
            let testSuites = suites.map { suiteName, tests in
                TestSuite(name: suiteName, targetName: targetName, tests: tests)
            }
            return TestTarget(name: targetName, suites: testSuites)
        }
    }
}
