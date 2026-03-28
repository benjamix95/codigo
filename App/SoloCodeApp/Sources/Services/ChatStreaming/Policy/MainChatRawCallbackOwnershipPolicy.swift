import Foundation

func shouldSplitStreamingAssistantOnRawTurnStarted(
    shouldApplyPipelineArtifacts: Bool,
    shouldUseLinearChat: Bool
) -> Bool {
    shouldApplyPipelineArtifacts && shouldUseLinearChat
}

func shouldProjectRawAssistantUpdateIntoLiveChat(
    shouldApplyPipelineArtifacts: Bool,
    providerId: String
) -> Bool {
    shouldApplyPipelineArtifacts && providerId == "codex-cli"
}
