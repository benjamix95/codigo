# Finding: toggle Plan → prima risposta poi si ferma

- **Stato**: fix UI + fix bridge Rust + NDJSON trace opzionale.
- **Causa root (UI)**: `resetPlanFlowAfterAbortedPreflight` quando il prompt plan è vuoto sulla stessa conversazione (evita `planFlowPhase` incollato a `.analyzing`).
- **Causa root (bridge, evidenza log A/C)**: `nilSnap=1` + `empty_screening_prompt_after_bridge` — **`apply_plan_runtime_action`** richiedeva `state.runtime_snapshot`; al **primo** messaggio in Plan non esiste ancora uno snapshot (nessun direct stream) → l’intent falliva **prima** di `plan_prepare_phase0_screening_prompt` → Swift vedeva `planRuntimeAction == nil`.
- **Fix Rust** (`plan_ui_flow.rs`): `runtime_snapshot_for_plan_action` — se `runtime_snapshot` manca, seed minimo con `selected_conversation_id` e `MainChatTurnState` idle. Test: `ui_intent_plan_phase0_screening_seeds_runtime_when_snapshot_missing`.

## NDJSON (`PlanFlowDebugNDJSONLog`)

File `.cursor/debug-773578.log`: marker A–E per lunghezze prompt e `preflight_abort` con `reason`.
