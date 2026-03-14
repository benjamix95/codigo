import Foundation

struct CodeReviewStreamTextAccumulator {
    private var chunks: [String] = []

    mutating func consume(_ event: StreamEvent) {
        switch event {
        case .textDelta(let delta):
            chunks.append(delta)
        case .textReplace(let replacement):
            chunks = [replacement]
        default:
            break
        }
    }

    var text: String {
        chunks.joined()
    }
}

extension CodeReviewMultiSwarmProvider {
    struct ReviewTask: Sendable {
        let id: String
        let description: String
        let files: [String]
        let severity: String
        let category: String?
        let lineNumber: Int?
        let endLineNumber: Int?
        let origin: FindingOrigin
        let confidence: Double?
        let evidence: String?
        let expectedInvariant: String?
        let reproOrReasoning: String?
        let sourceTool: String?
        let blocking: Bool?
    }

    enum ReviewTaskExtractionResult: Sendable {
        case tasks([ReviewTask])
        case noFixes
        case invalidJSON(reason: String)
        case noPayload(reason: String)
    }

    enum ReviewFindingsState: Sendable {
        case issues
        case clean
        case inconclusive(reason: String)
    }

    enum TestExecutionResult: Sendable {
        case passed
        case failed
        case inconclusive(reason: String)
    }

    enum ReviewFileScope: String, Sendable {
        case uncommitted
        case staged
        case workspace
    }

    enum ReviewPipelineError: Error, LocalizedError {
        case analysisTransportFailed(String)
        case analysisReturnedNoData

        var errorDescription: String? {
            switch self {
            case .analysisTransportFailed(let reason):
                "Analysis stream failed: \(reason)"
            case .analysisReturnedNoData:
                "Analysis completed without text output."
            }
        }
    }

    enum ExtractedReviewTasks: Sendable {
        case jsonTasks([ReviewTask])
        case invalidJSON(reason: String)
    }

    enum ParsedTasksResult: Sendable {
        case tasks([ReviewTask])
        case invalidJSON(reason: String)
    }

    struct ReReviewOutcome: Sendable {
        let text: String
        let findings: ReviewFindingsState
    }

    enum ReviewPipelineRunOutcome: Sendable, Equatable {
        case completed
        case failed(reason: String)
        case cancelled
    }

    static func findingsStateDebugLabel(for text: String) -> String {
        switch findingsContainIssues(text) {
        case .issues: return "issues"
        case .clean: return "clean"
        case .inconclusive: return "inconclusive"
        }
    }

    static func sortedWorkerTaskIDsForDisplay(_ ids: [String]) -> [String] {
        ids.sorted(by: sortWorkerTaskIDForDisplay(_:_:))
    }

    static func sortWorkerTaskIDForDisplay(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}
