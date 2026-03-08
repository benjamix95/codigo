import Foundation

// MARK: - Test Discovery

/// Scopre i test disponibili nel progetto usando `swift test --list-tests`.
actor TestDiscovery {
    /// Scopre tutti i test disponibili.
    func discoverTests(projectPath: String) async -> [TestTarget] {
        let result = await runProcess(
            arguments: ["test", "--list-tests", "--package-path", projectPath]
        )

        guard result.exitCode == 0 else { return [] }
        return parseTestList(from: result.stdout)
    }

    /// Parsa l'output di `swift test --list-tests`.
    /// Formato: `TargetName.SuiteName/testMethodName`
    func parseTestList(from output: String) -> [TestTarget] {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var targetMap: [String: [String: [TestCase]]] = [:]

        for line in lines {
            // Pattern: TargetName.SuiteName/testMethodName
            let components = line.split(separator: "/", maxSplits: 1)
            guard components.count == 2 else { continue }

            let qualifiedSuite = String(components[0])
            let testName = String(components[1])

            let suiteParts = qualifiedSuite.split(separator: ".", maxSplits: 1)
            let targetName: String
            let suiteName: String

            if suiteParts.count == 2 {
                targetName = String(suiteParts[0])
                suiteName = String(suiteParts[1])
            } else {
                targetName = "Default"
                suiteName = qualifiedSuite
            }

            let testCase = TestCase(
                name: testName,
                suiteName: suiteName,
                targetName: targetName
            )

            targetMap[targetName, default: [:]][suiteName, default: []].append(testCase)
        }

        return targetMap.map { targetName, suites in
            let testSuites = suites.map { suiteName, tests in
                TestSuite(name: suiteName, targetName: targetName, tests: tests)
            }.sorted { $0.name < $1.name }
            return TestTarget(name: targetName, suites: testSuites)
        }.sorted { $0.name < $1.name }
    }

    // MARK: - Private

    private func runProcess(arguments: [String]) async -> TestProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = arguments

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
}

struct TestProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
