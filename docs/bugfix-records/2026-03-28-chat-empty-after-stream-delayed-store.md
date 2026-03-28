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
