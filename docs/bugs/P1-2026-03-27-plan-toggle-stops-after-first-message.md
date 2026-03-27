# Finding: toggle Plan → prima risposta poi si ferma

- **Stato**: fix UI + fix bridge Rust + NDJSON trace opzionale.
- **Causa root (UI)**: `resetPlanFlowAfterAbortedPreflight` quando il prompt plan è vuoto sulla stessa conversazione (evita `planFlowPhase` incollato a `.analyzing`).
- **Causa root (bridge, evidenza log A/C)**: `nilSnap=1` + `empty_screening_prompt_after_bridge` — **`apply_plan_runtime_action`** richiedeva `state.runtime_snapshot`; al **primo** messaggio in Plan non esiste ancora uno snapshot (nessun direct stream) → l’intent falliva **prima** di `plan_prepare_phase0_screening_prompt` → Swift vedeva `planRuntimeAction == nil`.
- **Seconda causa (post-seed, evidenza codice Swift/Rust, conferma log F)**: La risposta intent tornava **success** lato Rust, ma il **decode JSON Swift** della `MainChatUIState` falliva: il seed usava `MainChatTurnState` con `..Default::default()` → `assistant_message_id` / a volte `conversation_id` **stringhe vuote**, mentre `MainChatBridgeState` decodifica UUID **non** vuoti → `ReviewCoreBridge.call` ritorna `nil` → `nilSnap=1` senza `state` Rust in errore.
- **Fix Rust** (`plan_ui_flow.rs`): (1) allinea `selected_conversation_id` da `request.conversation_id` quando manca; (2) errore esplicito `missing_conversation_for_plan` se non c’è snapshot né conversazione; (3) seed con `assistant_message_id` e `turn_id` placeholder validi per decode Swift. Test: `ui_intent_plan_phase0_screening_seeds_runtime_when_snapshot_missing`.

## NDJSON (`PlanFlowDebugNDJSONLog`)

File `.cursor/debug-773578.log`: marker A–E per lunghezze prompt e `preflight_abort` con `reason`; **H** = blocco policy `todo_first_required` (*Todo required before execution*) in `shouldHardBlockForMissingTodoOrPlan`; **I** = buffer pending stream sovrascritto prima del flush (`stream_pending_buffer_overwrite`) e commit `stream_replace_text` verso store (`stream_replace_text_commit`, throttled ~350ms + `stream_replace_throttle_rollup`); **J** = duplicazione “vecchia” lista todo/plan in chat vs overlay composer (`plan_markdown_hidden_gate`, `suppress_plan_artifacts_assistant`, `assistant_message_render_gate`, `chat_turn_visible_blocks`, `plan_artifact_card_rendered`, `composer_todo_overlay_visible`, `legacy_todo_card_in_chat_flag`).

## Finding 2026-03-27 (post bridge-fix): chat “in loop” su *Starting codebase analysis…*

- **Evidenza**: log A/B/D con `nilSnap=0` ma UI con più bolle uguali; Phase 1 manda lo stream soprattutto al **Plan panel** (`updatePlanStreamingContent`), mentre la bolla chat restava sulla stessa riga usata per screening + stato post-screening.
- **Causa**: stessa stringa per (1) placeholder screening, (2) messaggio dopo `plan_apply_screening_result` (Swift + Rust), (3) percezione di stallo durante Phase 1.
- **Fix UX copy**: placeholder screening distinto; post-screening / Rust `plan_screening_status_message` allineato a *Plan mode: running in-depth codebase analysis…*; prima di `runStream` in Phase 1 messaggio che indica stream nel Plan panel.

## Log verifica post-fix (773578)

- **H assente**: niente `todo_plan_start_policy_block` → esenzione discovery ok.
- **I**: `stream_replace_text_commit` con `prevStoreLen`/`textLen` in crescita durante screening; dopo **D** il primo commit Phase 1 ha `prevStoreLen` ~46 mentre lo screening aveva portato il testo a ~417 caratteri → la bolla è stata **sostituita** da `updateLastAssistantMessage(screeningStatus)` (testo corto post-screening), poi Phase 1 fa di nuovo replace con lo stream analisi.

## FAQ (architettura)

- **Perché non è “chat normale + Plan” con pipeline agent / subagent?** `executeSendMessageTurn` con `isPlanMultiTurnFlow` forza `MainChatSendExecutionRoute.planFlow` → `runMultiTurnPlanFlow` e sole chiamate `flowCoordinator.runStream` (Rust transport). **Non** passa da `agentPipeline` (`PipelineIntegrationService` + `AgentWorkerAdapter`). Inoltre, con provider Rust, la modalità agent usa spesso `.standardStream` invece della pipeline Swift se `usesRustTransport` (vedi `resolveMainChatSendExecutionRoute`).
- **Perché sembra che i messaggi si sovrascrivano?** (1) Un solo `assistantMessageId` per il turno utente. (2) `stream_replace_text` sostituisce **sempre** l’intero contenuto della bolla con l’ultimo snapshot testuale. (3) Dopo lo screening, `updateLastAssistantMessage(screeningStatus)` **cancella** il transcript lungo dello screening e lascia solo la riga di stato breve, poi Phase 1 ripopola la stessa bolla.
- **Tool “nostri” vs bash nativi**: in questo percorso il modello parla col provider (es. codex-cli) via runtime Rust; i tool effettivi dipendono da cosa espone quel provider nella sessione. La **pipeline agent** SoloCode (MCP orchestrato, swarm, ecc.) non è agganciata al branch `planFlow`.

## Fix 2026-03-27 (evidenza H): `todo_first_required` durante Plan discovery

- **Log**: `todo_plan_start_policy_block` con `planFlowPhase=analyzing`, `coderMode=agent`, `codex-cli`, `command_execution`, `didSeeTodoWrite=0` → hard-block interrompe Phase 1 (`CancellationError`).
- **Fix**: in `shouldHardBlockForMissingTodoOrPlan` non applicare il blocco se `planFlowPhase` è `.analyzing`, `.questioning` o `.generating` (fasi discovery prima di proposal/build).

## Finding 2026-03-27: log senza `phase1_after_analysis_stream` + richieste UX trace/composer

- **Evidenza**: `.cursor/debug-773578.log` con `phase1_generated_prompt` ma spesso senza riga E — output Phase 1 ancora in volo, errore non gestito in UI, o task principale marcato completato mentre i poll Rust continuano.
- **Fix streaming (parità con chat normale)**: Phase 0/1 chiamano `mirrorPlanDiscoveryStreamTextToChat` e `applyPlanDiscoveryStreamRawEvent` (`stream_apply_raw_event` + `handleRawStreamEvent`), così testo e tool compaiono nella **timeline chat** come nello stream standard.
- **Plan Trace solo in build**: `PlanLiveTraceView` nel pannello attività e nel **Plan panel** solo se `planFlowPhase == .building` (analisi → niente trace nel pannello Plan).
- **Composer todos (runtime)**: `TodoStore.displayTodosForComposer` include placeholder operativi per fasi Plan fino a `readyToBuild`; `hasVisibleComposerTodoOverlay` considera todo non-`done` anche se `isOperationalPlaceholder`.
- **NDJSON G**: `phase1_stream_begin` / `phase1_stream_completed` / `phase1_stream_error` in `PartM_MultiTurnPlanFlowPhase1`.

## Strumentazione J (2026-03-27): lista piano / todo ancora visibile in timeline chat

**Ipotesi da verificare con log**

1. **J1**: `shouldRoutePlanStreamingToPanel == false` in `ChatPanelView+DisplayFlags` → `shouldHidePlanMarkdownInChat` esce subito `false` → `suppressPlanArtifacts` quasi sempre spento → markdown piano resta in chat.
2. **J2**: Anche con `suppress` attivo, `chatDisplayMessage` sostituisce solo `content`; **`resolvedTimelineBlocks`** conserva `primaryText`/`.plan` → la lista numerata o la card artifact restano renderizzate.
3. **J3**: Blocco timeline `kind == plan` in `ArtifactCardView` (non filtrato da `ChatTurnTimelineOrdering.visibleBlocks`) → doppia presentazione rispetto al composer.
4. **J4**: `shouldShowPlanTodosInChat` (legacy) true in fase agent/build idle con todo canonici → `shouldShowTodo` / trace filter divergono dall’overlay (overlay sempre attivo).

**Interpretazione rapida log J**

- `plan_markdown_hidden_gate`: `hidden=0` + `shouldRoutePlanStreamToPanel=0` → conferma **J1** finché non si riallinea il routing o si filtra la timeline.
- `assistant_message_render_gate` vs `chat_turn_visible_blocks`: `suppressPlanArtifacts=1` ma `blockKinds` con `primaryText` lungo o `plan` → conferma **J2/J3**.
- `plan_artifact_card_rendered` → render esplicito artifact piano in chat (**J3**).
- `composer_todo_overlay_visible` insieme a `assistant_message_render_gate` con molti blocchi testo checklist → duplicazione UI (**J4** + markdown).

## Fix 2026-03-27 (evidenza J): duplicazione piano / todo in chat vs composer

- **Evidenza**: `shouldRoutePlanStreamingToPanel=0` → `hidden=0` nonostante `fullLooksLikePlanPayload=1` e `displayContentLen` ~11k; `composer_todo_overlay_visible` con 17 item; `shouldShowTodoCardInTurn=1` sul messaggio `3f7604d1-…` mentre il target todo era lo stesso thread.
- **Fix (prima iterazione, rollback UX)**: nascondere il markdown del piano in chat era stato richiesto per eliminare il duplicato, ma il piano in chat deve restare **fallback** visibile (come prima). La checklist duplicata è soprattutto **overlay composer** sopra lo stesso contenuto già in timeline.
- **Fix attuale**:
  1. **Niente** `hiddenByComposerParity` su `planMarkdownHiddenInChat`; **`chatDisplayMessage`** di nuovo solo sostituzione `content` quando il routing panel richiede soppressione.
  2. **`shouldSuppressComposerTodoWhenDuplicatePlanMarkdownInChat` Overlay** solo se ci sono **todo canonici** del piano **e** un messaggio con intestazione strutturata `## Plan` / `## Todo` / `## Piano` (≥ 400 caratteri). Le sole checklist `- [ ]` senza quelle sezioni **non** nascondono più l’overlay (todo classici nel composer).
  3. **`shouldShowPlanTodosInChat`**: tornato al comportamento precedente (senza gate composer).
