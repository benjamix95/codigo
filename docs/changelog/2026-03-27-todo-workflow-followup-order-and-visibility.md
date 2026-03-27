# Changelog — 2026-03-27 — Todo workflow follow-up/order/visibility

## Obiettivo

Rifare la pipeline todo per:
- creare checklist reali anche per scan/analisi multi-fase;
- mantenere una sequenza unica e coerente tra store, UI e prompt;
- rendere `Code Review & Test` una fase condizionale e `Doc Writer` l’ultimo passo reale delle checklist multi-fase;
- lasciare i completed visibili con strikethrough senza riordinarli fuori sequenza.

## Modifiche principali

### 1. Policy centralizzata per classificazione e follow-up

Aggiornati:
- `App/SoloCodeApp/Sources/Tasking/Support/TodoExecutionFollowUpPolicy.swift`
- `App/SoloCodeApp/Sources/Tasking/Support/TodoExecutionFollowUpPolicy+Classification.swift`

Cosa fa:
- classifica i titoli come analisi, implementazione, validazione, documentazione o placeholder non valido;
- espande i single-step troppo generici in fasi reali:
  - analisi: `Definire scope` -> task reale -> `Consolidare findings / output`;
  - implementazione: `Analizzare target` -> task reale;
- riappende i follow-up finali solo quando servono davvero:
  - implementazione: `Code Review & Test` -> `Doc Writer`;
  - analisi multi-fase: `Doc Writer`.

### 2. Ordinamento condiviso e sequenza rigorosa

Modificato:
- `App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+RuntimeExecutionProgression.swift`
- `App/SoloCodeApp/Sources/Tasking/TodoSummaryCardView.swift`

Cosa cambia:
- il runtime promuove solo il primo todo non terminale della coda;
- un item `blocked` precedente blocca i successivi;
- le summary card non riordinano più i todo per stato ma rispettano l’ordine fornito dallo store.

### 3. Prompt e UI allineati alla stessa checklist

Modificati:
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartO_Streaming1.swift`
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartO_TodoPromptSection.swift`
- `Engine/CoderEngine/Sources/SystemPrompts/Policies/PromptExecutionPolicy.swift`

Cosa cambia:
- il prompt istruisce il modello a creare todo reali per ogni task multi-fase, anche scan/audit/analisi;
- `Current todos` viene serializzato nell’ordine della coda runtime, senza sort per stato;
- la policy globale non impone più `Code Review & Test` come obbligo universale fuori contesto.

### 4. Pipeline e follow-up runtime coerenti con la policy nuova

Modificato:
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_TodoEvents.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventMapping.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventMappingSupport.swift`
- `App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+FollowUpGating.swift`

Cosa cambia:
- il runtime aggiunge solo i follow-up finali mancanti e coerenti con la checklist in scope;
- la pipeline canonical continua a ignorare follow-up non autorizzati dal piano;
- review/doc non vengono più promossi come side-effect generici.

## Test aggiunti/aggiornati

Aggiunti:
- `Tests/SoloCodeAppTests/TodoPromptSectionTests.swift`

Aggiornati:
- `Tests/SoloCodeAppTests/TodoExecutionFollowUpPolicyTests.swift`
- `Tests/SoloCodeAppTests/TodoExecutionRuntimeFollowUpTests.swift`
- `Tests/SoloCodeAppTests/TodoStoreTests.swift`
- `Tests/SoloCodeAppTests/ChatPanelTodoFinalizationTests.swift`
- `Tests/SoloCodeAppTests/PipelineIntegrationServiceTests.swift`
- `Tests/SoloCodeAppTests/ComposerTodoOverlayStateTests.swift`

## Verifica eseguita

Comando usato:
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/TodoExecutionFollowUpPolicyTests -only-testing:SoloCodeAppTests/TodoExecutionRuntimeFollowUpTests -only-testing:SoloCodeAppTests/TodoPromptSectionTests -only-testing:SoloCodeAppTests/TodoStoreTests -only-testing:SoloCodeAppTests/ComposerTodoOverlayStateTests -only-testing:SoloCodeAppTests/ChatPanelTodoFinalizationTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests`

Esito:
- `103 test`, `0 failure`
- `** TEST SUCCEEDED **`

## Note

- La suite macOS ha ricompilato anche i componenti Rust/Xcode collegati al target applicativo; non sono emersi failure bloccanti, solo warning preesistenti non in scope.
- In questa sessione `xcodebuildmcp` non era disponibile tra i tool esposti; per il target macOS ho usato `xcodebuild` diretto come fallback verificabile.
