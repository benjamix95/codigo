import CoderEngine
import Foundation

extension VerifiedFindingsPatchExecutionService {
    static func openPullRequestContext(
        finding: CodeReviewFinding
    ) throws -> ReviewPatchOpenPRContext {
        let response: ReviewPatchOpenPRContextResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_open_pr_context",
            request: ReviewPatchOpenPRContextRequest(
                schemaVersion: 1,
                filePath: finding.filePath,
                message: finding.message,
                verificationReport: finding.verificationReport
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                "Rust patch open pr context runtime required but unavailable"
            )
        }
        if response.isError {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                response.message ?? "Unable to derive patch open pr context"
            )
        }
        guard let title = response.title, let body = response.body else {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                "Rust patch open pr context response was incomplete"
            )
        }
        return ReviewPatchOpenPRContext(title: title, body: body)
    }
}

struct ReviewPatchOpenPRContext {
    let title: String
    let body: String
}

struct ReviewPatchOpenPRContextRequest: Encodable {
    let schemaVersion: Int
    let filePath: String
    let message: String
    let verificationReport: String?
}

struct ReviewPatchOpenPRContextResponse: Decodable {
    let isError: Bool
    let message: String?
    let title: String?
    let body: String?
}
