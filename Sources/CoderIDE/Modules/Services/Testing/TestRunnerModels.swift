import Foundation

// MARK: - Test Runner Models

/// Stato di un singolo test.
enum TestStatus: String, Codable, Sendable {
    case pending
    case running
    case passed
    case failed
    case skipped
}

/// Un singolo test case.
struct TestCase: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let name: String
    let suiteName: String
    let targetName: String
    var status: TestStatus
    var duration: TimeInterval?
    var failureMessage: String?
    var filePath: String?
    var line: Int?

    init(
        name: String,
        suiteName: String,
        targetName: String,
        status: TestStatus = .pending,
        filePath: String? = nil,
        line: Int? = nil
    ) {
        self.id = "\(targetName)/\(suiteName)/\(name)"
        self.name = name
        self.suiteName = suiteName
        self.targetName = targetName
        self.status = status
        self.filePath = filePath
        self.line = line
    }
}

/// Una suite di test (contenitore di test case).
struct TestSuite: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let targetName: String
    var tests: [TestCase]

    var passedCount: Int { tests.filter { $0.status == .passed }.count }
    var failedCount: Int { tests.filter { $0.status == .failed }.count }
    var totalCount: Int { tests.count }

    init(name: String, targetName: String, tests: [TestCase] = []) {
        self.id = "\(targetName)/\(name)"
        self.name = name
        self.targetName = targetName
        self.tests = tests
    }
}

/// Un target di test.
struct TestTarget: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    var suites: [TestSuite]

    var passedCount: Int { suites.reduce(0) { $0 + $1.passedCount } }
    var failedCount: Int { suites.reduce(0) { $0 + $1.failedCount } }
    var totalCount: Int { suites.reduce(0) { $0 + $1.totalCount } }

    init(name: String, suites: [TestSuite] = []) {
        self.id = name
        self.name = name
        self.suites = suites
    }
}

/// Risultato di un'esecuzione di test.
struct TestRunResult: Sendable {
    let targets: [TestTarget]
    let totalDuration: TimeInterval
    let exitCode: Int32
    let error: String?

    var isSuccess: Bool { error == nil && failedCount == 0 }
    var passedCount: Int { targets.reduce(0) { $0 + $1.passedCount } }
    var failedCount: Int { targets.reduce(0) { $0 + $1.failedCount } }
    var totalCount: Int { targets.reduce(0) { $0 + $1.totalCount } }

    static func failure(error: String) -> TestRunResult {
        TestRunResult(targets: [], totalDuration: 0, exitCode: 1, error: error)
    }
}

/// Dati di code coverage per un singolo file.
struct FileCoverage: Identifiable, Codable, Sendable {
    let id: String
    let filePath: String
    let coveredLines: Int
    let executableLines: Int
    var lineHits: [Int: Int]   // lineNumber → hitCount

    var coveragePercentage: Double {
        guard executableLines > 0 else { return 0 }
        return Double(coveredLines) / Double(executableLines) * 100
    }

    init(filePath: String, coveredLines: Int, executableLines: Int, lineHits: [Int: Int] = [:]) {
        self.id = filePath
        self.filePath = filePath
        self.coveredLines = coveredLines
        self.executableLines = executableLines
        self.lineHits = lineHits
    }
}

/// Risultato complessivo di code coverage.
struct CoverageReport: Sendable {
    let files: [FileCoverage]
    let totalCoveredLines: Int
    let totalExecutableLines: Int
    let error: String?

    var overallPercentage: Double {
        guard totalExecutableLines > 0 else { return 0 }
        return Double(totalCoveredLines) / Double(totalExecutableLines) * 100
    }

    var isSuccess: Bool { error == nil }

    static func failure(error: String) -> CoverageReport {
        CoverageReport(files: [], totalCoveredLines: 0, totalExecutableLines: 0, error: error)
    }
}
