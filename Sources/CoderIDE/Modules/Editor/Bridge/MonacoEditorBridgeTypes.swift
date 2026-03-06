import Foundation

struct MonacoEditorOptions: Equatable, Sendable {
    var readOnly = false
    var wordWrap = false
    var minimapEnabled = true
}

struct MonacoEditorBridgeHandlers {
    let onContentChange: (String, String) -> Void
    let onSaveRequested: (String) -> Void
    var onFixInChat: ((String, String, Int) -> Void)?
    var onAddToChat: ((String, String, Int) -> Void)?
    var onCursorChange: ((EditorCursorPosition) -> Void)?
    var onSelectionChange: ((EditorSelectionRange) -> Void)?
    var onMarkersChanged: ((MonacoMarkerPayload) -> Void)?
    var onActionInvoked: ((MonacoActionPayload) -> Void)?
    var hoverProvider: ((MonacoRequestContext) async -> MonacoHoverPayload)?
    var definitionProvider: ((MonacoRequestContext) async -> MonacoDefinitionPayload)?
    var referencesProvider: ((MonacoRequestContext) async -> MonacoDefinitionPayload)?
    var renameProvider: ((MonacoRequestContext) async -> MonacoRenamePayload)?
    var outlineProvider: ((MonacoRequestContext) async -> MonacoOutlinePayload)?
}
