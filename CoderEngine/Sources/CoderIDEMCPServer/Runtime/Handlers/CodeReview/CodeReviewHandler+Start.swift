import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handleReviewStart(args: [String: String]) -> CallTool.Result {
        let scope = sanitizedReviewArg(args, key: "scope").lowercased()
        let validScopes: Set<String> = ["uncommitted", "staged", "against_ref"]

        let effectiveScope = scope.isEmpty ? "uncommitted" : scope
        if !validScopes.contains(effectiveScope) {
            return reviewError(
                "Error: invalid scope '\(scope)'. Use: uncommitted, staged, against_ref"
            )
        }

        if effectiveScope == "against_ref" {
            let ref = sanitizedReviewArg(args, key: "ref")
            if ref.isEmpty {
                return reviewError(
                    "Error: 'ref' parameter is required when scope=against_ref"
                )
            }
        }

        // Validate optional numeric parameters
        if let maxWorkersStr = args["max_workers"],
           !maxWorkersStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let val = Int(maxWorkersStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...12).contains(val) else {
                return reviewError("Error: max_workers must be 1-12")
            }
        }

        if let maxRoundsStr = args["max_rounds"],
           !maxRoundsStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let val = Int(maxRoundsStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...10).contains(val) else {
                return reviewError("Error: max_rounds must be 1-10")
            }
        }

        return reviewOK("OK — code review started with scope: \(effectiveScope)")
    }

    static func handleReviewStatus(args: [String: String]) -> CallTool.Result {
        // Read real session state from shared disk file
        let status = MCPSharedState.readCodeReviewStatus()
        if status["phase"] == "idle" && status.count <= 2 {
            return reviewOK("No active review session.")
        }
        let lines = status.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }
        return reviewOK(lines.joined(separator: "\n"))
    }

    static func handleReviewDiffSummary(args: [String: String]) -> CallTool.Result {
        // Read-only: diff summary is computed on the UI side from git state.
        return reviewOK("OK — diff summary requested")
    }
}
