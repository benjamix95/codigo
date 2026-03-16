import Foundation

public enum ReviewDiffSummaryRustBridge {
    public static func renderSummary(
        snapshot: CodeReviewSessionSnapshot,
        workspacePath: URL,
        fileFilter: String? = nil,
        filteredFiles: [String]? = nil
    ) -> String? {
        let request = ReviewDiffSummaryRustRequest(
            schemaVersion: 1,
            snapshot: snapshot,
            workspacePath: workspacePath.path,
            fileFilter: fileFilter,
            filteredFiles: filteredFiles
        )
        let response: ReviewDiffSummaryRustResponse? = ReviewCoreBridge.call(
            functionName: "review_core_render_diff_summary",
            request: request
        )
        guard response?.error == nil else {
            return nil
        }
        return response?.summary
    }
}

private struct ReviewDiffSummaryRustRequest: Encodable {
    let schemaVersion: Int
    let snapshot: CodeReviewSessionSnapshot
    let workspacePath: String
    let fileFilter: String?
    let filteredFiles: [String]?
}

private struct ReviewDiffSummaryRustResponse: Decodable {
    let error: ReviewDiffSummaryRustError?
    let summary: String
}

private struct ReviewDiffSummaryRustError: Decodable {
    let code: String
    let message: String
}
