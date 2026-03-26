import Foundation

extension PipelineJobFactory {
    static func sanitizeDebugId(_ text: String) -> String {
        let cleaned = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return String(cleaned.prefix(40))
    }

    static func timeoutForDebugStage(_ stage: DebugStageKind) -> Int {
        switch stage {
        case .describePipelineBootstrap, .reproducePipelineBootstrap, .fixPipelineBootstrap:
            return 90_000
        case .activateMode, .sessionStart, .sessionExport, .sessionStop,
             .setDescribePhase, .setReproducePhase, .setFixPhase,
             .setVerifyPhase, .resolve:
            return 45_000
        case .requestClarification:
            return 60_000
        case .requestReproduction:
            return 60_000
        case .awaitReproduceGate, .awaitFixGate:
            return 600_000 // 10 min — user must reproduce/test before confirming
        case .hostReproduceGateAck:
            return 5_000
        case .verify:
            return 180_000
        case .nativeStart, .nativeRefresh, .nativeSyncBreakpoints,
             .nativeSyncWatches, .nativeStepIn, .nativeStepOver,
             .nativeStepOut, .nativeStop:
            return 90_000
        case .gatherContext, .analyzeIssue, .reproduce,
             .instrument, .snapshot, .hypothesize,
             .fix, .reviewFix, .clean, .timeline:
            return 120_000
        }
    }

    static func riskForDebugStage(_ stage: DebugStageKind) -> RiskLevel {
        switch stage {
        case .describePipelineBootstrap, .reproducePipelineBootstrap, .fixPipelineBootstrap, .activateMode, .sessionStart, .sessionExport, .sessionStop,
             .setDescribePhase, .setReproducePhase, .setFixPhase,
             .setVerifyPhase, .requestClarification, .requestReproduction,
             .resolve, .awaitReproduceGate, .hostReproduceGateAck, .awaitFixGate:
            return .low
        case .gatherContext, .analyzeIssue, .reviewFix, .verify,
             .snapshot, .hypothesize, .timeline:
            return .medium
        case .reproduce, .instrument, .fix, .clean,
             .nativeStart, .nativeRefresh, .nativeSyncBreakpoints,
             .nativeSyncWatches, .nativeStepIn, .nativeStepOver,
             .nativeStepOut, .nativeStop:
            return .high
        }
    }

    static func preferredRoleForDebugStage(
        _ stage: DebugStageKind
    ) -> AgentRole? {
        stage.defaultAgentRole ?? .debugger
    }

    static func debugBaseMetadata(
        stage: DebugStageKind,
        request: DebugSessionRequest,
        metadata: [String: String]
    ) -> [String: String] {
        var merged = metadata
        merged["debug_stage"] = stage.rawValue
        merged["debug_phase"] = stage.defaultPhase.rawValue
        merged["backend_policy"] = request.backendPolicy.rawValue
        merged["include_native_stages"] = request.includeNativeStages ? "true" : "false"
        if !request.errorSummary.isEmpty {
            merged["error_summary"] = request.errorSummary
        }
        if let targetPath = request.targetPath, !targetPath.isEmpty {
            merged["target_path"] = targetPath
        }
        if !request.arguments.isEmpty {
            merged["arguments"] = request.arguments.joined(separator: "\n")
        }
        if !request.workspaceHints.isEmpty {
            merged["workspace_hints"] = request.workspaceHints.joined(separator: "\n")
        }
        if !request.watchExpressions.isEmpty {
            merged["watch_expressions"] = request.watchExpressions.joined(separator: "\n")
        }
        if let breakpointsJSON = encodeDebugNativeBreakpoints(request.breakpoints) {
            merged["native_breakpoints_json"] = breakpointsJSON
        }
        return merged
    }

    static func encodeDebugNativeBreakpoints(
        _ breakpoints: [DebugNativeBreakpointSpec]
    ) -> String? {
        guard !breakpoints.isEmpty else { return nil }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(breakpoints) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
