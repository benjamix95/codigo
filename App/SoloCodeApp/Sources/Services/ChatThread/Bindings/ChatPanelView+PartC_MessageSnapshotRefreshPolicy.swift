import Foundation

struct ChatPanelPipelineSnapshotRefreshPlan {
    let refreshChromeRuntimeSnapshot: Bool
    let refreshMessagesSnapshot: Bool
}

func chatPanelPipelineSnapshotChangeRefreshPlan() -> ChatPanelPipelineSnapshotRefreshPlan {
    // Il publisher della pipeline serve a riallineare il chrome/runtime.
    // Il refresh completo dei messaggi ha già trigger indipendenti
    // (`chatStore.objectWillChange` e `streaming.streamContentVersion`),
    // quindi qui evitiamo un secondo passaggio completo della lista.
    ChatPanelPipelineSnapshotRefreshPlan(
        refreshChromeRuntimeSnapshot: true,
        refreshMessagesSnapshot: false
    )
}
