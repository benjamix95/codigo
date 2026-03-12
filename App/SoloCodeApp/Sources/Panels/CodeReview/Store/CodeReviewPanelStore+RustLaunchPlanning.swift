import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func planPanelReviewLaunch() -> (sessionId: String, config: SessionConfig)? {
        let selectedBackend = selectedProviderOverrideId ?? ""
        let resolvedAnalysisBackend = selectedBackend.isEmpty ? settings.analysisBackend : selectedBackend
        let resolvedExecutionBackend = selectedBackend.isEmpty ? settings.executionBackend : selectedBackend
        return planPanelLaunch(
            sessionPrefix: panelSessionPrefix,
            config: SessionConfig(
                maxWorkers: settings.maxWorkers,
                maxRounds: settings.maxRounds,
                analysisBackend: resolvedAnalysisBackend,
                executionBackend: resolvedExecutionBackend,
                analysisOnly: settings.analysisOnly
            )
        )
    }

    func planPanelTargetedFixLaunch(
        sourceSnapshot: CodeReviewSessionSnapshot
    ) -> (sessionId: String, config: SessionConfig)? {
        planPanelLaunch(
            sessionPrefix: "\(sourceSnapshot.sessionId)-fix",
            config: sourceSnapshot.config
        )
    }

    private func planPanelLaunch(
        sessionPrefix: String,
        config: SessionConfig
    ) -> (sessionId: String, config: SessionConfig)? {
        let response: ReviewPanelStartPlanResponse? = ReviewCoreBridge.call(
            functionName: "review_core_command_plan",
            request: ReviewPanelStartPlanRequest(
                schemaVersion: 1,
                action: "start",
                sessionId: nil,
                payload: [
                    "max_workers": "\(config.maxWorkers)",
                    "max_rounds": "\(config.maxRounds)",
                    "analysis_backend": config.analysisBackend,
                    "execution_backend": config.executionBackend,
                    "analysis_only": config.analysisOnly ? "true" : "false",
                    "session_prefix": sessionPrefix,
                ],
                workspaceAvailable: !workspaceStore.activeWorkspacePaths.isEmpty,
                snapshotExists: false,
                currentConfig: nil,
                defaultConfig: ReviewPanelStartPlanConfig(
                    maxWorkers: config.maxWorkers,
                    maxRounds: config.maxRounds,
                    analysisBackend: config.analysisBackend,
                    executionBackend: config.executionBackend,
                    analysisOnly: config.analysisOnly
                )
            )
        )

        guard let response,
              !response.isError,
              let sessionId = response.sessionId,
              let config = response.config else {
            return nil
        }
        return (
            sessionId,
            SessionConfig(
                maxWorkers: config.maxWorkers,
                maxRounds: config.maxRounds,
                analysisBackend: config.analysisBackend,
                executionBackend: config.executionBackend,
                analysisOnly: config.analysisOnly
            )
        )
    }

    var panelSessionPrefix: String {
        if selectedModes == [.standard] {
            return "panel"
        }
        return primarySelectedMode.rawValue
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    func rerunScopeTarget(for snapshot: CodeReviewSessionSnapshot) -> ReviewScopeTarget {
        switch snapshot.scope?.type {
        case .againstRef:
            return .againstRef(snapshot.scope?.ref ?? "HEAD~1")
        case .staged:
            return .staged
        case .workspace:
            return .workspace
        case .uncommitted, .none:
            return .uncommitted
        }
    }
}

private struct ReviewPanelStartPlanRequest: Encodable {
    let schemaVersion: Int
    let action: String
    let sessionId: String?
    let payload: [String: String]
    let workspaceAvailable: Bool
    let snapshotExists: Bool
    let currentConfig: ReviewPanelStartPlanConfig?
    let defaultConfig: ReviewPanelStartPlanConfig
}

private struct ReviewPanelStartPlanConfig: Codable {
    let maxWorkers: Int
    let maxRounds: Int
    let analysisBackend: String
    let executionBackend: String
    let analysisOnly: Bool
}

private struct ReviewPanelStartPlanResponse: Decodable {
    let isError: Bool
    let sessionId: String?
    let config: ReviewPanelStartPlanConfig?
}
