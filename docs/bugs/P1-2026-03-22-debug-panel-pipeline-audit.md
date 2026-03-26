# Debug Panel Pipeline Audit

- Data: 2026-03-22
- Area: Debug Panel, debug tools, projection, runtime, MCP bridge
- Categoria: A/B mista
- Obiettivo: individuare colli di bottiglia, bug, drift contrattuali e rischi infrastrutturali nella pipeline del debug panel

## Perimetro
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/DebugPanel/*`
  - `App/SoloCodeApp/Sources/Debug/*`
  - `App/SoloCodeApp/Sources/Services/Debug/*`
  - `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/*DebugProjection*`
  - `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Debug/*`
  - `Engine/CoderEngine/Sources/AgentPipeline/Debug/*`
  - `Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/*`
  - `Tools/CoderIDEMCPServer/Sources/Tools/Catalog/CoderIDETools+Debug.swift`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CoderIDEMCPServerApp+IDEStateTools.swift`
  - `Native/CoderideMCPServerRust/src/debug_tools.rs`
  - test e doc collegate
- Non-scope:
  - fix runtime o refactor architetturali
  - code review di aree non collegate al debug panel

## Sintesi Esecutiva
La pipeline del debug panel oggi ha un problema principale: il contratto dichiarato al modello, il catalogo MCP, il runtime Swift, il fallback Rust, la projection UI e la copertura test non sono allineati. Questo produce una suite che sembra completa dal prompt, ma in realtà è parziale o incoerente in più punti critici.

I problemi più gravi sono quattro:
- session lifecycle non coerente tra policy e job pipeline
- verify path quasi inutilizzabile su workspace Xcode
- fallback Rust che conferma operazioni senza eseguirle davvero
- perdita o desincronizzazione di eventi tra projection, buffering e panel UI

## Findings Prioritari

### P1 — `debug_request_user` supporta `fix_confirmation` nel contratto ma non nell'handler IDE
- Impatto:
  - il gate finale di verify/cleanup può fallire o essere rifiutato nonostante sia richiesto dalla policy
- Evidenza:
  - catalogo tool accetta `question`, `reproduce`, `fix_confirmation` in [CoderIDETools+Debug.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Tools/Catalog/CoderIDETools+Debug.swift#L228)
  - handler IDE accetta solo `question|reproduce` in [CoderIDEMCPServerApp+IDEStateTools.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CoderIDEMCPServerApp+IDEStateTools.swift#L156)
  - projection UI gestisce `fix_confirmation` in [DebugProjectionEventConsumer.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/Debug/DebugProjectionEventConsumer.swift#L104)
- Rischio:
  - drift silenzioso tra tool catalog, UI e runtime orchestration
- Intervento consigliato:
  - allineare subito l'handler IDE a `fix_confirmation`
  - aggiungere test contrattuale catalogo -> handler -> mapper -> projection

### P1 — La pipeline richiede `debug_session` ma il job flow non la avvia in modo affidabile
- Impatto:
  - log, snapshots, query e persistence possono vivere fuori sessione o con scoping incompleto
- Evidenza:
  - policy impone `debug_session action=start` in [PromptToolsPolicy.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/SystemPrompts/Policies/PromptToolsPolicy.swift#L60)
  - la factory del flow non crea uno stage iniziale dedicato `debug_session` in [PipelineJobFactory+Debug.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/AgentPipeline/Debug/Factory/PipelineJobFactory+Debug.swift#L224)
  - il runtime usa stato sessione dedicato in [UnifiedToolRuntime+DebugSession.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Debug/Session/UnifiedToolRuntime+DebugSession.swift#L9)
- Rischio:
  - session summary e session-bound query non affidabili
- Intervento consigliato:
  - introdurre stage hard-required `debug_session start`
  - fallire il flow se si entra in debug senza sessione attiva

### P1 — `debug_test_check` è monco per questo repository
- Impatto:
  - la fase VERIFY è strutturalmente debole sui flussi iOS/macOS del progetto
- Evidenza:
  - il tool rifiuta workspace senza `Package.swift` in [UnifiedToolRuntime+DebugTestCheck.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Debug/Context/UnifiedToolRuntime+DebugTestCheck.swift#L11)
  - esegue solo `swift test` in [UnifiedToolRuntime+DebugTestCheck.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Debug/Context/UnifiedToolRuntime+DebugTestCheck.swift#L23)
- Rischio:
  - false confidence in verify
  - pipeline diversa da quella reale usata nel prodotto
- Intervento consigliato:
  - aggiungere backend `xcodebuild`/`xcodebuildmcp` come path primario per app/workspace Xcode
  - lasciare `swift test` solo come fallback per package puri

### P1 — Il fallback Rust dei debug tools è in larga parte stubbed
- Impatto:
  - può rispondere `OK` senza eseguire davvero cleanup, instrumentation, resolve o snapshot compare coerenti
- Evidenza:
  - `coderide_debug_resolve`, `coderide_debug_mark`, `coderide_debug_clean`, `coderide_debug_instrument` restituiscono solo testo statico in [debug_tools.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/debug_tools.rs#L39)
  - `debug_snapshot` non supporta `capture|compare|list`, ma solo dump dello store in [debug_tools.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/debug_tools.rs#L206)
  - `debug_test_check` non esegue test reali in [debug_tools.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/debug_tools.rs#L239)
- Rischio:
  - comportamento diverso tra backend Swift e backend Rust
  - regressioni invisibili quando il server Rust è attivo
- Intervento consigliato:
  - o portare il Rust host alla stessa parity dello Swift runtime
  - oppure disabilitare esplicitamente i tool debug non ancora implementati

### P1 — `debug_context` è un tool monolitico e costoso
- Impatto:
  - latenza elevata, output troncato, rumore e possibile timeout nelle prime fasi del debug
- Evidenza:
  - esegue `git status`, `git diff`, `git log`, `swift build`, `read_lints`, `swift test list`, env probes e crash scan nella stessa chiamata in [UnifiedToolRuntime+DebugContext.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Debug/Context/UnifiedToolRuntime+DebugContext.swift#L16)
- Rischio:
  - chiamata costosa usata troppo presto nel flow
  - accoppiamento eccessivo tra diagnosi, build e test discovery
- Intervento consigliato:
  - spezzare il tool in sotto-tool o sub-scope lazy
  - evitare `swift build` e `swift test list` in default path

### P1 — Gli eventi debug possono perdersi durante suspend/resume della projection
- Impatto:
  - panel desincronizzato, phase gate persi, richiesta utente o resolve non visibili
- Evidenza:
  - `suspendDebugProjection` svuota il buffer in [PipelineIntegrationService+DebugProjection.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+DebugProjection.swift#L21)
  - in stato suppress gli eventi vengono scartati in [PipelineIntegrationService+DebugProjection.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+DebugProjection.swift#L53)
- Rischio:
  - perdita silenziosa di eventi di pipeline
- Intervento consigliato:
  - bufferizzare e fare replay, non drop
  - introdurre test su late registration, resume, switch thread, close/reopen panel

### P1 — Doppio buffering debug tra `ChatPanelView` e `PipelineIntegrationService`
- Impatto:
  - replay non deterministico e possibili divergenze tra sorgenti UI
- Evidenza:
  - buffer UI in [ChatPanelView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView.swift#L217)
  - routing dedicato in [ChatPanelView+PartP_DebugRouting.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/Debug/ChatBindings/ChatPanelView+PartP_DebugRouting.swift#L21)
  - buffer service-side in [PipelineIntegrationService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService.swift#L42)
- Rischio:
  - ownership dello stato non chiara
- Intervento consigliato:
  - scegliere un solo owner del buffer debug
  - rendere l'altro livello puramente pass-through

### P1 — I tool avanzati debug non arrivano come stato strutturato al panel
- Impatto:
  - `trace_analyze`, `timeline`, `snapshot`, `test_check` vengono normalizzati come aggiornamenti debug generici, ma non guidano lo stato del panel
- Evidenza:
  - il normalizer li classifica come debug tool updates in [EventNormalizerCore.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/EventNormalizer/Core/EventNormalizerCore.swift#L35)
  - non esistono eventi typed equivalenti in [EventNormalizerModels.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/EventNormalizer/Core/EventNormalizerModels.swift)
  - il consumer UI non li gestisce in [DebugProjectionEventConsumer.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/Debug/DebugProjectionEventConsumer.swift#L24)
- Rischio:
  - tooling più ricco del panel, ma senza projection affidabile
- Intervento consigliato:
  - aggiungere typed events dedicati o una projection stateful per questi tool

### P2 — `debug_snapshot compare` ha semantica ambigua
- Impatto:
  - chi usa il tool si aspetta confronto tra due snapshot persistiti, ma il runtime confronta uno snapshot salvato con lo stato corrente
- Evidenza:
  - implementazione compare in [UnifiedToolRuntime+DebugTimelineSnapshot.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Debug/Analysis/UnifiedToolRuntime+DebugTimelineSnapshot.swift#L155)
- Rischio:
  - risultati fuorvianti e difficile automazione
- Intervento consigliato:
  - supportare confronto `label` vs `compare_with` su snapshot persistiti veri
  - rinominare il path attuale se si vuole mantenere la semantica “current state”

### P2 — `debug_resolve` può essere ignorato mentre aspetta `debug_clean`
- Impatto:
  - summary finale persa o divergente da quella prodotta dalla pipeline
- Evidenza:
  - ignore esplicito in [DebugProjectionEventConsumer.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/Debug/DebugProjectionEventConsumer.swift#L115)
  - summary finale ricostruita localmente con `pendingResolutionAfterClean` in [DebugStore+Markers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Debug/Stores/DebugStore+Markers.swift#L37) e [DebugStore+Cleanup.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Debug/Stores/DebugStore+Cleanup.swift#L3)
- Rischio:
  - resolve race
- Intervento consigliato:
  - accodare `debug_resolve` quando `awaitingDebugClean == true`
  - preservare il summary originale del tool event

### P2 — Capability sandbox `.debug` non è allineata alla suite documentata
- Impatto:
  - plugin o estensioni in modalità debug vedono una superficie diversa da quella documentata
- Evidenza:
  - allowlist `.debug` incompleta in [PluginCapabilitySandbox.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/Extensions/PluginCapabilitySandbox.swift#L12)
  - suite completa documentata in `docs/SOLOCODE_PIPELINE_V2.md`
- Rischio:
  - drift persistente tra docs, runtime e plugin ecosystem
- Intervento consigliato:
  - test di parità automatico tra catalogo tool, capability sandbox e docs

### P2 — Stato UI frammentato in flag e stringhe distribuite
- Impatto:
  - CTA e stato backend possono divergere
- Evidenza:
  - flags sparse in [DebugStore.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Debug/DebugStore.swift#L50)
  - update distribuiti tra consumer e actions in [DebugProjectionEventConsumer.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/Debug/DebugProjectionEventConsumer.swift#L91) e [DebugPanelView+Actions.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/DebugPanel/DebugPanelView+Actions.swift#L79)
- Rischio:
  - transizioni parziali e UX incoerente
- Intervento consigliato:
  - introdurre un vero state machine owner per il flow

## Gap di Test
- Copertura E2E limitata all’happy path base in [DebugFlowToolE2ETests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/DebugFlowToolE2ETests.swift#L5)
- Mancano test E2E su:
  - `debug_trace_analyze`
  - `debug_snapshot`
  - `debug_timeline`
  - `debug_test_check`
  - mismatch catalogo -> normalizer -> projection
- Mancano test di parity tra:
  - catalogo MCP debug
  - handler IDE state
  - fallback Rust
  - capability sandbox

## Colli di Bottiglia Operativi
- `debug_context` è troppo costoso per essere il primo colpo di debug
- `debug_test_check` non usa il backend di test giusto per un workspace Xcode
- il fallback Rust oggi abbassa l’affidabilità percepita della suite
- la proiezione eventi ha più di un owner e può perdere dati

## Ordine di Intervento Consigliato
1. Allineare contratto `fix_confirmation`, `debug_session` e suite `.debug` tra catalogo, handler, policy e sandbox.
2. Rendere affidabile il verify path con backend `xcodebuild`/`xcodebuildmcp`.
3. Eliminare drop e doppio buffering nella projection.
4. Portare a parity il fallback Rust oppure disabilitare i tool non implementati.
5. Introdurre typed events e test E2E per la suite avanzata.
6. Spezzare `debug_context` in operazioni lazy e più economiche.

## Aggiornamento stato (post-fix 2026-03-26)

Interventi già integrati nel codice rispetto ai finding originari:

- **P1 fix_confirmation vs handler IDE**: handler accetta `question`, `reproduce`, `fix_confirmation`.
- **P1 `debug_session` nel DAG**: stage `session_start` dopo describe bootstrap, prima di `gatherContext`.
- **P1 `debug_test_check` Xcode**: percorso Swift con validation config + `xcodebuild` (non solo `swift test` su Package).
- **P1 default `debug_context`**: scope default leggero (`git,env`); `full` / `lints` espliciti.
- **P1 Rust stub massiccio**: mark/clean/instrument/snapshot/test_check e compare snapshot ampliati in `debug_tools.rs`; `debug_request_user` documenta che la UI panel richiede bridge IDE (`ide_bridge_required_for_panel_ui`).
- **Proiezione / buffer**: limite coda aumentato (1500); teardown con `DebugStore` ancora registrato **applica** i pending anche se la proiezione era soppressa (`resolvePendingDebugEventsBeforeTeardown`).
- **Snapshot compare**: Swift e Rust supportano confronto tra due snapshot persistiti + fallback verso stato corrente.
- **Sandbox plugin `.debug`**: include `activate_debug_mode`.

Restano aree di attenzione (non chiuse al 100%):

- ~~Due percorsi di ingresso~~ (2026-03-26): `routeDebugEvent` usa solo `applyOrBufferDebugEvent`; `persistDebugState` è nel `applyEffects` della registrazione store.
- Overflow buffer con trim: possibile perdita di eventi a **bassa** priorità.
- `debug_trace_analyze` ancora euristico (Swift e Rust).
- Test E2E end-to-end sulla suite debug avanzata da espandere.

## Nota Finale
L’audit originale (2026-03-22) descriveva lo stato pre-fix. La sezione **Aggiornamento stato** riflette il codice a fine marzo 2026. I finding storici nella parte centrale del documento vanno letti con questo contesto.
