# Changelog — 2026-03-27 — Debug User Opt-In Enforcement

## Obiettivo
Impedire all'agente di entrare in modalità debug o di aprire il debug panel senza opt-in esplicito dell'utente tramite toggle.

## Modifiche applicate

### Gate centrale opt-in debug
- Aggiunto [`DebugUserOptInPolicy.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/Debug/Support/DebugUserOptInPolicy.swift) con helper condivisi per:
  - validare l'opt-in utente
  - demotare `.debug` a `.agent` quando il toggle è spento
  - bloccare projection/debug activity senza toggle

### Blocco dell'auto-attivazione debug
- Aggiornato [`ChatPanelView+PartG_AutoActivation.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/Debug/ChatBindings/ChatPanelView+PartG_AutoActivation.swift) per ignorare `activate_debug_mode` se il toggle utente non è attivo.
- Aggiornato [`ChatPanelView+PartP_DebugRouting.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/Debug/ChatBindings/ChatPanelView+PartP_DebugRouting.swift) per non applicare projection/effects debug quando manca opt-in.
- Aggiornato [`ChatPanelView+PartI_RuntimeHelpers.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatProviders/Bindings/ChatPanelView+PartI_RuntimeHelpers.swift) per evitare che sync provider/conversation riporti la chat in `.debug` senza toggle.

### Lifecycle e pipeline
- Aggiornato [`ChatPanelView+LifecycleModifiers.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+LifecycleModifiers.swift) per richiudere il panel se qualcuno prova ad aprirlo senza toggle e per riportare la chat in `.agent` quando il toggle viene spento.
- Aggiornati [`ChatPanelView+DebugPipelineIntents.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/DebugPipeline/ChatBindings/ChatPanelView+DebugPipelineIntents.swift) e [`ChatPanelView+DebugPipelineNativeIntents.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/DebugPipeline/ChatBindings/ChatPanelView+DebugPipelineNativeIntents.swift) per rifiutare l'esecuzione di pipeline debug senza toggle attivo.

### Rimozione del lessico debug non autorizzato
- Aggiornato [`ChatPanelView+PartF_DebugTodoEvents.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_DebugTodoEvents.swift) per non mostrare task activity debug quando l'utente non ha attivato il toggle.
- Aggiornato [`EventNormalizerDebug.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/EventNormalizer/Debug/EventNormalizerDebug.swift) per non creare più l'activity user-facing di `activate_debug_mode`.

### Policy del prompt
- Aggiornato [`PromptToolsPolicy.swift`](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/SystemPrompts/Policies/PromptToolsPolicy.swift) per vietare esplicitamente l'uso auto-attivante di `activate_debug_mode` finché il toggle utente non è già attivo.

### Test
- Aggiunti [`DebugUserOptInPolicyTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/DebugUserOptInPolicyTests.swift) per coprire gate, demotion mode e filtro activity.
- Aggiornati [`SystemPromptsTests.swift`](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/SystemPromptsTests.swift) per verificare la nuova policy testuale.

## Validazione
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/DebugUserOptInPolicyTests -only-testing:CoderEngineTests/SystemPromptsTests`
- Esito: `TEST SUCCEEDED`
