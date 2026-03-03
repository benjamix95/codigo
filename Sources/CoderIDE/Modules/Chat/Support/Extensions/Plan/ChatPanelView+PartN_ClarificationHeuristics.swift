import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func userExplicitlyWantsClarifications(_ userRequest: String) -> Bool {
        let normalized = userRequest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return normalized.range(
            of: #"(chiedi|fammi|poni).{0,20}(domande|chiarimenti)|ask.{0,20}(questions|clarifications)"#,
            options: .regularExpression
        ) != nil
    }

    internal func shouldAskPlanClarifications(analysisText: String, userRequest: String) -> Bool {
        if userExplicitlyWantsClarifications(userRequest) {
            return true
        }

        let normalized = "\(analysisText)\n\(userRequest)".lowercased()
        let blockingPatterns: [String] = [
            #"\b(blocked|cannot proceed|can't proceed|impossible to proceed)\b"#,
            #"\b(missing requirement|missing decision|decision needed|unknown requirement)\b"#,
            #"\b(ambiguous|unclear|not enough information|insufficient information)\b"#,
            #"\b(conflicting requirement|conflicting constraints|trade[- ]off not specified)\b"#,
            #"\b(need clarification|requires clarification|clarification required)\b"#,
        ]
        var hits = 0
        for pattern in blockingPatterns {
            if normalized.range(of: pattern, options: .regularExpression) != nil {
                hits += 1
            }
        }
        return hits >= 3
    }

    internal func shouldAllowFollowUpClarification(
        userRequest: String,
        clarificationCycles: Int
    ) -> Bool {
        // Keep a single clarification round by default to avoid loops.
        guard clarificationCycles < 1 else {
            return false
        }
        return userExplicitlyWantsClarifications(userRequest)
    }
}
