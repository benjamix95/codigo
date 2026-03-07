import Foundation

extension CodeReviewMultiSwarmProvider {
    struct ReviewTask: Sendable {
        let id: String
        let description: String
        let files: [String]
        let severity: String
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
}
