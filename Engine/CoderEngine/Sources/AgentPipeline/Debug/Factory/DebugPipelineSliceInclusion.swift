import Foundation

enum DebugPipelineSliceInclusion {
    static func shouldIncludeStage(
        slice: DebugPipelineSlice,
        stage: DebugStageKind,
        request: DebugSessionRequest
    ) -> Bool {
        switch slice {
        case .full:
            return true
        case .intake:
            switch stage {
            case .describePipelineBootstrap, .sessionStart, .gatherContext,
                 .requestClarification, .analyzeIssue, .reproducePipelineBootstrap,
                 .awaitReproduceGate:
                return true
            default:
                return false
            }
        case .investigation:
            switch stage {
            case .hostReproduceGateAck:
                return request.includeNativeStages
            case .nativeStart, .nativeSyncBreakpoints, .nativeSyncWatches,
                 .reproduce, .instrument, .fixPipelineBootstrap, .snapshot,
                 .hypothesize, .fix, .reviewFix, .setVerifyPhase,
                 .verify, .awaitFixGate:
                return true
            default:
                return false
            }
        case .resolution:
            switch stage {
            case .clean, .nativeStop, .timeline, .sessionExport,
                 .resolve, .sessionStop:
                return true
            default:
                return false
            }
        }
    }
}
