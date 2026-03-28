# Bug Fix Record — 2026-03-28 — Chat vuota dopo stream / store ritardato

- **Categoria:** A — Critico (UI)
- **Sintomo:** la timeline può svuotarsi mentre il thread ha ancora messaggi; a volte torna dopo tempo o dopo resize.
- **Evidenza runtime (sessione `2fa5b8`, NDJSON):**
  - `render_branch_after_refresh` con `snapMsgCount: 2`, stesso `conversationId` (`11EE0A07-…`).
  - ~22s dopo: `snapshot_state_replaced` con `freshCount: 0` per lo **stesso** id (`log_1774642720208_…`).
  - Errore stream `missing_gemini_path` poco prima (`stream_error_failed`).
- **Causa:** `shouldPreserveSnapshotAgainstTransientEmptyStore` aveva `idleGraceWindow` 0.75s e `lastBusyAt` ancorato solo a `chromeBusy`; dopo un buco lungo lo store poteva ancora risultare vuoto rispetto allo snapshot e la policy sostituiva lo snapshot svuotando la lista.
- **Fix:**
  - `idleGraceWindow` predefinito portato a **30s**.
  - In `refreshMessagesSnapshot`, aggiornare `snapshotLastBusyAt` alla transizione **loading → idle** (`wasLoadingForPostTaskGrace && !freshLoading`) per iniziare la grace al termine reale del task.
- **File:** `ChatPanelView+PartC_MessageSnapshotPolicy.swift`, `ChatPanelView+PartC_MessageSnapshotRefresh.swift`, test `ChatPanelMessageSnapshotPolicyTests`.

## Follow-up 2026-03-28 (UI ancora “vuota” con dati ok)

- **Evidenza NDJSON post-fix:** in molte run `snapMsgCount` / `freshCount` restano **> 0** e **non** ricorre `freshCount: 0`; resta quindi plausibile **layout** (altezza area messaggi ~0) o **overlay** inconsistencies, non lo store.
- **Strumentazione:** `ChatPanelMessagesDebugModifier` su `ZStack` area messaggi — log `H20` (`messages_area_low_height` / `messages_area_height_drop`) e `H21` (`empty_overlay_shown` / `empty_overlay_hidden`) in `ChatPanelView+AgentDebugMessagesProbe.swift` + `PartC_MessageHeader.swift`.

### Fix 2 — auto-scroll vs snapshot (mar 2026)

- **Evidenza:** nella stessa finestra temporale compaiono H20 con `storeCount: 0` / `listHasConv: false` e subito dopo H8/H13 con messaggi nello snapshot; nessun `empty_overlay` e altezza ZStack ~696 — coerente con **scroll vietato** mentre la lista è già alimentata dallo snapshot.
- **Causa:** `scheduleAutoScroll` usava solo `chatStore` per `allowAnchorTargets` e per gli id messaggio; se lo store è indietro rispetto allo snapshot, `canScrollToTarget` bloccava lo scroll verso l’anchor basso durante il follow-live.
- **Fix:** `allowAnchorTargets` e `availableMessageIDs` tengono conto anche di `messagesConversationSnapshot` allineato al thread con messaggi non vuoti (`ChatPanelView+PartE_TaskLifecycle+Run.swift`). Log throttled `H22` se resta bloccato nonostante lo snapshot.

### Fix 3 — fine stream e coalesce scroll (mar 2026)

- **Evidenza:** run 2fa5b8 corto con `snapshotIsLoading` `true` → `false` (H12) e `snapMsgCount` stabile; nessun H22 — il blocco `canScrollToTarget` non è la sola causa. Possibile che l’ultimo `scrollTo` utile sia stato **saltato** dal coalesce 350ms sullo stesso target mentre il `LazyVStack` rimonta la history quando `snapshotIsLoading` diventa `false`.
- **Fix:** su `onChange(snapshotIsLoading)` quando diventa `false` e `isFollowingLive`, `scheduleAutoScroll(..., bypassCoalesce: true)` con leggero delay. Log throttled **H23**.

### Fix 4 — follow-live durante streaming (mar 2026)

- **Evidenza:** run 2fa5b8 lunga con **solo** H12 `to:true`, mai H23/`to:false`: `snapshotIsLoading` e `taskLoading` restano `true` mentre H10 ticka — la chat “sparisce” **a streaming attivo**, non solo a fine task. Il coalesce **350ms** sullo stesso anchor buttava via troppi `scrollTo` consecutivi.
- **Fix:** parametro `minCoalesceInterval` in `scheduleAutoScroll`; `handleStreamContentVersionChange` usa **120ms**. Log throttled **H24** (`autoscroll_bottom_executed`) per verificare che lo scroll parta durante lo stream.

### Fix 5 — eager `VStack` sotto soglia messaggi (mar 2026)

- **Evidenza:** con **H24** presente (`autoscroll_bottom_executed`) l’utente riproduce ancora timeline invisibile — `scrollTo` non è sufficiente; resta plausibile **LazyVStack** in `ScrollView` su macOS che non ridisegna il viewport fino a resize.
- **Fix:** per `messages.count ≤ 160` la colonna timeline usa **`VStack`**; oltre la soglia **`LazyVStack`** come prima (`ChatPanelView+PartD_MessagesStack.swift`, `ChatMessagesTimelineStack`).

### Fix 6 — snapshot fermo mentre `streamContentVersion` ticka (H11)

- **Evidenza:** `refresh_ran_but_snapshot_unchanged_while_active` (H11) con `freshLastContentLen` piatto (es. 569, 97, 177) per molti tick mentre `streamContentVersion` sale; a volte **`resolvedPrimaryText`** resta ferma perché `primaryTextSnapshot` non vuoto ma obsoleto mentre il delta sta in **`blocks[].text`**.
- **Causa:** `needsSnapshotUpdate` non confrontava l’universo testo **`resolvedTimelineBlocks`** (somma `text` + `items`).
- **Fix:** in `ChatPanelView+PartC_MessageSnapshotRefresh.swift`, oltre a `resolvedPrimaryText`, aggiungere `chatMessageTimelinePayloadCharSum` su `messages.last` al gate `needsSnapshotUpdate`. Log H11 arricchito con `freshTimelinePayloadLen`.

### Fix 7 — timeline live: pipeline + pending davanti allo store (mar 2026)

- **Evidenza:** H10 con `streamContentVersion` che salta (es. 12→13, 17, senza H8) mentre H11 mantiene `freshLastContentLen` costante (es. 97, 177, 331): il thread principale ticka ma `chatStore` + snapshot non ricevono ancora il commit; Fix 6 non basta se **fresh** e **snapshot** restano uguali tra loro.
- **Causa:** la lista legge solo `Conversation` dallo snapshot; testo/blocchi più freschi stanno in `pendingStreamContent` (throttle prima di `applyMainChatUIStreamIntent`) o in `PipelineConversationRuntime.chatTurnState` (tra i round-trip Rust/debounce).
- **Fix:** `messageForStreamingTimelineDisplay` fonde pending + `turn.blocks` / `primaryTextSnapshot` nel messaggio assistente attivo prima di `ChatTurnView` (`ChatPanelView+PartD_StreamingTimelineMerge.swift`, cella e riga streaming dedicated in `PartD_MessagesStack`). Log throttled **H25** (`streaming_timeline_merged_ahead_of_store`) quando il merge supera lo store.

### Fix 8 — Markdown streaming: cache per lunghezza UTF-16 (mar 2026)

- **Evidenza:** H11 con `freshLastContentLen` / `freshTimelinePayloadLen` **uguali** (es. 98) mentre `streamContentVersion` sale (13→19): il dato può essere aggiornato ma la UI no se il testo cambia **senza** cambiare `utf16.count`.
- **Causa:** `MarkdownContentView.buildStreamingAttributed` usava solo `lastStreamingAttributedLength` come chiave della cache statica.
- **Fix:** chiave sulla **stringa sorgente** (`lastStreamingAttributedSource == text`) prima di riusare `AttributedString` cache (`MarkdownContentView+Views.swift`). H25 log solo su merge materiale (`content` / `blocks` / `primaryTextSnapshot` / payload).

### Fix 9 — pending/pipeline vs blocco `primaryText` (mar 2026)

- **Evidenza:** H11 con payload fermo (es. `199`) mentre `streamContentVersion` sale; H25 con `storePayload` == `mergedPayload` e `hadPending: true` — il buffer c’è ma la timeline non si muove.
- **Causa:** con `blocks` non vuoti la UI legge il testo dal blocco `.primaryText`; aggiornare solo `content` / `primaryTextSnapshot` (e merge solo se `count` cresce) lasciava il blocco obsoleto; stessa lunghezza sostitutiva non passava il gate.
- **Fix:** confronto normalizzato con `resolvedPrimaryText` **e** con il testo del primo blocco primary; `applyLivePrimaryStreamText` aggiorna anche `blocks[idx].text` (`ChatPanelView+PartD_StreamingTimelineMerge.swift`).

### Fix 10 — ordine tool vs testo in streaming (mar 2026)

- **Sintomo:** durante lo stream, tutti i tool sopra e un unico blocco di risposta sotto; manca l’ordine atteso (testo / tool / testo…).
- **Causa:** merge UI che faceva `merged.blocks = pipelineBlocks` quando la pipeline aveva **meno** `toolMarker` del messaggio nello store. Senza marker, `ChatTurnTimelineInterleaver` classifica un solo `primaryText`(0) come monolitico e sposta il testo dopo tutti i tool (`maxToolSequence + 1`).
- **Fix:** se `pipeToolMarkers < baseToolMarkers`, aggiornare solo il testo primary con `applyLivePrimaryStreamText`, senza sostituire l’intera array di blocchi (`PartD_StreamingTimelineMerge.swift`).

### Fix 11 — ordine verticale: niente bump “monolitico” nell’interleaver (mar 2026)

- **Sintomo:** con trace tool popolate ma **nessun** `toolMarker` nei blocchi, tutte le card tool sopra e un unico blocco di risposta sotto (ordine non cronologico rispetto a `sequence`).
- **Causa:** `ChatTurnTimelineInterleaver` trattava il caso “un solo primaryText(0) + tool senza marker” spostando il testo a `maxToolSequence + 1`, quindi dopo tutti gli eventi tool.
- **Fix:** per `.primaryText` usare **sempre** `block.sequence` (rimossa l’euristica monolitica). Test `testInterleaverKeepsSinglePrimaryBeforeToolsWhenNoToolMarkers`. Log NDJSON throttled **H26** su `.cursor/debug-72ead1.log` per il caso monolitico senza marker (verifica post-fix: `preview` inizia con `0T`,…).

### Fix 12 — tie-break stabile a parità di `sequence` (mar 2026)

- **Evidenza:** log H26 con `preview` tipo `0R,0T,3G`: reasoning e primary condividono `sequence` 0; l’ordine dipendeva da `id` (UUID), quindi non garantito tra sessioni.
- **Fix:** ordinamento esplicito a parità di sequenza: reasoning → text → tool → subagent live → snapshot → artifact, poi `id`. Test `testInterleaverReasoningBeforeTextWhenSequenceEqualRegardlessOfId`.

### Fix 13 — `toolTraceArtifact` perso se il bridge Rust non restituisce stato (mar 2026)

- **Evidenza:** H26 con `traceCount` alto ma caso “no toolMarker” nei blocchi: `appendToolTraceEvent` chiama `applyChatPipelineEvent(.toolTraceArtifact)` per aggiungere un segmento `toolUse` in `ChatTurnState.timelineSegments` (vedi commento in `PartF_DebugTodoLifecycle.swift`). Se `applyPipelineEventThroughRustBoundary` restituisce `nil`, in produzione l’evento veniva scartato (non solo nei test con `shouldSkipRustStoreBootstrapForTests`), quindi `timelineSegments` restava vuota → fallback `blocks` monolitico senza marker.
- **Fix (storico):** fallback Swift quando Rust restituiva `nil`.

### Fix 14 — `toolTraceArtifact` sempre via Swift + emissione pipeline con turn fallback (mar 2026)

- **Evidenza post–Fix 13:** H26 ancora con `preview` tipo `0T,3G` e `traceCount` 88: il bridge Rust può **restituire stato** ma **senza** aggiornare correttamente `timelineSegments` per l’artifact, quindi il ramo Rust “vincente” lasciava i blocchi senza marker. Inoltre, se `currentAssistantPipelineTarget` era `nil`, l’evento `.toolTraceArtifact` non veniva proprio emesso.
- **Fix:** (1) In `applyChatPipelineEvent`, per `kind == .toolTraceArtifact` applicare **solo** `ChatPipelineReducer` + `ChatPipelineCommitter.commit`, senza passare dal bridge Rust. (2) In `appendToolTraceEvent`, usare `turn.assistantMessageId` e `turnId` derivato dal messaggio nello store se il pipeline target è `nil`.

### Fix 15 — RAM Swift senza `blocks` pipeline dopo `sync_assistant_pipeline_state` (mar 2026)

- **Evidenza post–Fix 14:** log **H26** (`monolithic_no_markers_merged_order`) con `traceCount` alto e `preview` tipo `0T,3G`: i trace ci sono ma **`toolMarker` assenti** nel messaggio letto dalla timeline.
- **Causa:** in `updateAssistantMessagePipelineState`, se `applyRustStoreAction` restituiva **`applied == true`**, il messaggio in `conversations` veniva sostituito con `pipelineMessage` **solo** quando il testo visibile locale era vuoto (`visible.isEmpty`). I blocchi prodotti in Swift (inclusi i marker) non aggiornavano mai la copia in RAM usata dalla UI.
- **Fix:** dopo un apply Rust riuscito, se `ChatTurnState.blocks` ha **più** blocchi o **più** `toolMarker` del messaggio locale, sostituire il messaggio con `pipelineMessage` (`ChatStore+PipelineStateLocalSync.swift`). Log NDJSON throttled **H32** (`rust_applied_local_blocks_sync`) su `.cursor/debug-72ead1.log`. Test `testPipelineCommitPropagatesToolMarkersWhenRustApplySucceeds`.

### Fix 16 — merge display streaming ignorava i marker (mar 2026)

- **Evidenza post–Fix 15:** ancora **H26** (`0T,3G` / `0T,4G`, `traceCount` alto) e **nessun H32**: pipeline e store spesso con **uguali** 0 marker nel commit, mentre il vero gap era la **UI in streaming**.
- **Causa:** `messageForStreamingTimelineDisplay` sostituiva `merged.blocks` con `turn.blocks` solo se `pipelinePayload > storePayload`. I blocchi `.toolMarker` hanno **testo vuoto** → non aumentano la somma caratteri; se lo store aveva già tutto il primary, il merge dei blocchi **non partiva mai**.
- **Fix:** considerare anche `streamingPipelineHasRicherBlockStructure` (più marker o più blocchi) indipendentemente dal delta payload. Log throttled **H33** (`pipeline_structure_merge_without_payload_delta`) su `.cursor/debug-72ead1.log` quando si applica quel ramo.

### Fix 17 — `toolTraceArtifact` senza `detail`: nessun marker, testo unito (mar 2026)

- **Sintomo:** più “risposte” nello stesso turno finiscono in **un solo** blocco primary (testo attaccato al precedente); in UI i tool compaiono ma l’ordine/testo resta monolitico (coerente con H26).
- **Causa:** in `ChatPipelineReducer`, `.toolTraceArtifact` chiamava `ensureToolSegment` **solo** se `detail` non era vuoto. Molti `appendToolTraceEvent` passano `detail: activity.detail ?? ""` vuoto → la timeline non riceveva `.toolUse`, ultimo segmento restava `.text`, e i `textDelta` seguenti continuavano sullo stesso `textSegments` index.
- **Fix:** chiamare sempre `ensureToolSegment` per `.toolTraceArtifact`; `upsertArtifact` solo se c’è testo. Log throttled **H34** (`tool_trace_marker_despite_empty_detail`). Test `testReducerSplitsTextWhenToolTraceArtifactHasEmptyDetail`.

### Fix 18 — due `chatTurnState`: trace aggiorna solo `conversationRuntime` (mar 2026)

- **Evidenza:** con Fix 17 compaiono **H34** (reducer ok) ma **H26** resta (`0T,3G`): la UI non vede mai i `toolMarker` nel messaggio mostrato.
- **Causa:** `applyChatPipelineEvent(.toolTraceArtifact)` aggiorna `conversationRuntime.activeTurnStateByConversation`, mentre `messageForStreamingTimelineDisplay` legge `pipelineIntegrationService.runtime(for:)?.chatTurnState` (stato della job pipeline). I marker non venivano mai copiati lì → merge/display ancora monolitico.
- **Fix:** dopo commit Swift per `.toolTraceArtifact`, `mirrorToolTraceArtifactIntoActivePipelineRuntime` applica lo stesso evento a `PipelineConversationRuntime.chatTurnState` se conversation + `assistantMessageId` coincidono. Log throttled **H35** (`tool_trace_mirrored_into_pipeline_runtime`).

### Fix 19 — merge streaming senza job `PipelineIntegrationService` (mar 2026)

- **Evidenza:** ancora **H26** + **H34** ma **nessun H35**: `runtime(for:)` spesso `nil` (chat senza job pipeline attivo o già teardown), quindi il mirror Fix 18 non gira.
- **Causa:** `messageForStreamingTimelineDisplay` usava solo `pipelineIntegrationService.runtime`; `applyChatPipelineEvent` aggiorna `conversationRuntime.activeTurnStateByConversation` comunque.
- **Fix:** risolvere `ChatTurnState` per il merge come **integration runtime se valido**, altrimenti **`conversationRuntime.activeTurnStateByConversation`**. Log throttled **H36** (`merge_uses_conversation_runtime_not_integration`).

### Fix 20 — merge blocchi solo su “superficie streaming attiva” (mar 2026)

- **Evidenza:** **H36** con `pipeMarkers: 1` ma **H26** ancora (anche `0T,3G` / `0T,4G`): il primo passaggio merge esiste, ma molte istanze della cella arrivano al interleaver **senza** marker (store grezzo).
- **Causa:** `messageForStreamingTimelineDisplay` faceva `return base` subito se mancava uno tra `isStreaming && snapshotIsLoading && id == active`. La riga in **history** (`ForEach` su `historyMessages`) o i frame con snapshot non allineato non applicavano mai i `blocks` con `toolMarker` pur avendo trace.
- **Fix:** stesso guard solo per assistente; il buffer `pendingStreamContent` resta legato a `isActiveStreamingSurface`. Log throttled **H37** (`pipeline_blocks_merged_outside_active_streaming_surface`).

### Fix 21 — `ChatTurnState` per `assistantMessageId` (turno successivo sovrascrive `active`) (mar 2026)

- **Evidenza:** ancora **H26** con `traceCount` alto (`88`) mentre **H33/H36** mostrano `pipeToolMarkers: 1` su *un altro* passaggio: `activeTurnStateByConversation[convId]` punta al **nuovo** turno, quindi il messaggio assistente **precedente** non matcha più e il merge non applica i blocchi con `toolMarker`.
- **Causa:** uno **solo** stato pipeline per conversazione sull’hash `activeTurnStateByConversation`; alla nuova risposta assistente si perde il puntatore allo stato del messaggio history.
- **Fix:** `ChatConversationRuntimeState.pipelineTurnStateByAssistantMessageId`, aggiornato ad ogni commit in `PipelineLegacyChatAdapter.applyChatPipelineEvent`; il merge usa integration → active (se stesso `assistantMessageId`) → **cache per `base.id`**. Log throttled **H38** (`merge_uses_assistant_message_pipeline_cache`, `runId`: `streaming-assistant-cache21`).

### Fix 22 — timeline Rust vuota vs marker Swift; marker per ogni `toolTraceArtifact` (mar 2026)

- **Evidenza post–Fix 21:** **H26** ancora (`0T,3G` / `traceCount` 88), **nessun H38**; **H33** con `pipeToolMarkers: 1` nello stesso run → il turno usato a frame alterni ha **`timelineSegments` vuoti** o **un solo** `.toolUse` per molti artifact: `ChatTurnState.blocks` genera **zero** `toolMarker` per l’interleaver pur con trace ricche.
- **Cause:** (1) `ensureToolSegment` non appendeva un nuovo `.toolUse` se l’ultimo segmento era già tool → **un marker** per **N** `toolTraceArtifact` consecutivi. (2) Il round-trip `applyPipelineEventThroughRustBoundary` può restituire `timelineSegments == []` mentre lo stato Swift precedente conteneva già `.toolUse` da `toolTraceArtifact` → stato attivo **senza** marker fino al prossimo commit.
- **Fix:** `appendDistinctToolSegment` per `.toolTraceArtifact`; `ChatTurnState.reconcilingTimelineWhenRustReturnedEmptyWhileSwiftHadToolMarkers` applicata al risultato Rust; log throttled **H39** (`rust_empty_timeline_reused_swift_tool_segments`, `runId`: `rust-timeline-reconcile22`). Test: `testReducerConsecutiveToolTraceArtifactsEachInsertsMarker`, `testReconcileRestoresSwiftTimelineWhenRustReturnsEmptySegments`.
