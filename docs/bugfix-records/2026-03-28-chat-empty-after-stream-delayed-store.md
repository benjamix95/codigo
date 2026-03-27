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

### Fix 5 — snapshot fermo mentre `streamContentVersion` ticka (H11)

- **Evidenza:** `refresh_ran_but_snapshot_unchanged_while_active` (H11) con `freshLastContentLen` piatto (es. 569) per molti tick, poi `snapshot_state_replaced` quando `content` salta (es. 1036): durante lo stream il testo live sta spesso in **`primaryTextSnapshot`**, non in `content`.
- **Causa:** `needsSnapshotUpdate` confrontava solo `messages.last.content` / blocks / reasoning, non **`resolvedPrimaryText`** (che preferisce `primaryTextSnapshot`).
- **Fix:** in `ChatPanelView+PartC_MessageSnapshotRefresh.swift`, aggiungere `snapshotLastResolvedPrimary != freshLastResolvedPrimary` al gate `needsSnapshotUpdate`.
