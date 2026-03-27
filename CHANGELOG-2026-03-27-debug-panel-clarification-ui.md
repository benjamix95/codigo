# Changelog — 2026-03-27 — Debug Panel Clarification UI

## Obiettivo
Correggere il flusso di chiarimento del debug panel in due punti:
- rendere selezionabili anche le opzioni inline `A/B/C...`
- non mostrare in chat il contenuto completo della risposta inviata dal panel

## Modifiche applicate

### Parser prompt debug
- Esteso [`DebugClarificationPromptParser`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/DebugPanel/Parsing/DebugClarificationPromptParser.swift) per riconoscere anche marker inline `A)`, `B)`, `C)` nella stessa riga.
- Mantenuto il comportamento esistente per i prompt multi-linea già supportati.
- Aggiunta deduplica delle lettere prima di costruire le opzioni visualizzate.

### Submit del debug panel
- Introdotto [`DebugClarificationSubmission`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/DebugPanel/DebugClarificationSubmission.swift) per separare:
  - payload reale per l’agente (`agentPrompt`)
  - testo visibile in chat (`chatDisplayText`)
- Aggiornata la card [`DebugPanelView+ClarificationResponseCard.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/DebugPanel/DebugPanelView+ClarificationResponseCard.swift) per usare il composer tipizzato invece di serializzare direttamente una stringa.
- Aggiornato [`ChatPanelView+DebugClarificationSubmit.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/DebugPipeline/ChatBindings/ChatPanelView+DebugClarificationSubmit.swift) in modo che la chat mostri solo `altro` mentre il prompt completo continua ad arrivare all’agente.
- Aggiornato il wiring del panel in [`DebugPanelView.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/DebugPanelView.swift) e [`ChatPanelView+PartB_SidebarsAndSwarm.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartB_SidebarsAndSwarm.swift).

### Test di regressione
- Estesi [`DebugClarificationPromptParserTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/DebugClarificationPromptParserTests.swift) con copertura per opzioni inline su singola riga.
- Aggiunti [`DebugClarificationSubmissionComposerTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/DebugClarificationSubmissionComposerTests.swift) per verificare masking della chat e payload reale verso l’agente.

## Validazione
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS'`
- Esito: fallito per errore preesistente fuori scope in [`PipelineIntegrationService+EventMappingSupport.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventMappingSupport.swift), dove viene letto `canonicalTodoCompletionRoles` definito `private` in [`PipelineIntegrationService+EventMapping.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventMapping.swift).
- Nessun errore aggiuntivo del fix emerso nel perimetro modificato prima del blocco della build.
