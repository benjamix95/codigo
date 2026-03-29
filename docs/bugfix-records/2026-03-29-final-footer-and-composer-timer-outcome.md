# Bugfix Record — 2026-03-29

## Scope
- Rendere visibile subito il footer finale del task quando il turno assistant è terminale ma conserva un flag streaming stale.
- Colorare il timer del composer in base all'esito reale del task.

## Modifiche
- Aggiornato [`ChatStreamFinalizerHelpers.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Utilities/ChatStreamFinalizerHelpers.swift) per considerare terminali i messaggi assistant con `turnMetadata.status` completato/fallito/cancellato o `completedAt` valorizzato, anche se `isStreaming` è rimasto stale.
- Esteso [`ComposerFrozenTimerState`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+ComposerPlanHelpers.swift) con un `tone` semantico e aggiornato il builder `buildComposerFrozenTimerState`.
- Propagato l’outcome del task nel composer tramite [`ChatPanelSupport+PanelViewStateStructs.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+PanelViewStateStructs.swift), [`ChatPanelSupport+ChatPanelViewComposerPlanAccessors.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+ChatPanelViewComposerPlanAccessors.swift), [`ChatPanelView+PartE_ToolTraceTurn.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartE_ToolTraceTurn.swift) e [`ChatPanelView+LifecycleModifiers.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+LifecycleModifiers.swift).
- Estratta la UI del timer runtime in [`ChatComposerView+RuntimeTimer.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView+RuntimeTimer.swift) e collegata a [`ChatComposerView.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView.swift), [`ChatComposerView+ComposerBox.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView+ComposerBox.swift) e [`ChatPanelView+PartH_ComposerArea.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+PartH_ComposerArea.swift).

## Test
- [`ChatPanelFinalActionsVisibilityTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatPanelFinalActionsVisibilityTests.swift)
- [`ComposerRuntimeTimerTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ComposerRuntimeTimerTests.swift)

## Rischi controllati
- Nessun cambio al layout del footer finale.
- Nessun cambio all’ordering della timeline.
- Nessun cambio ai controlli runtime del composer oltre al tone del timer finale.
