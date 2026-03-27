# Finding: toggle Plan → prima risposta poi si ferma

- **Stato**: fix stato UI + **tracciamento runtime** per la causa profonda.
- **Causa root (UI)**: prompt plan vuoti lasciavano `planFlowPhase == .analyzing`; `cleanupPlanFlowAfterConversationSwitch` non resetta sulla stessa conversazione → **fix**: `resetPlanFlowAfterAbortedPreflight` (fasi 0–3) con **reason** testuale.
- **Causa profonda (da provare con log)**: `planRuntimeAction` / Rust non popola `output.generatedPrompt` per fase 0 o 1 → `genLen=0`, `nilSnap=1` o `nilGenPromptField=1` nei marker.

## NDJSON Plan trace (`PlanFlowDebugNDJSONLog`)

File: `.cursor/debug-773578.log` (append, una riga JSON per evento).

| hypothesisId | Significato |
|----------------|-------------|
| **A** | `phase0_generated_prompt` — risposta bridge screening (`genLen`, `nilSnap`, `nilGenPromptField`). |
| **B** | `phase1_generated_prompt` — stesso per analisi. |
| **C** | `preflight_abort` — `reason` = quale guard ha fatto reset (`empty_phase1_prompt_after_bridge`, …). |
| **D** | `phase0_after_screening_stream` — lunghezza output LLM dopo screening, `skipFullPipeline`. |
| **E** | `phase1_after_analysis_stream` — lunghezza analisi, se serve chiarimenti. |

Dopo riproduzione: leggere in ordine le righe per vedere se il blocco è **prima** dello stream (prompt bridge vuoto) o **dopo** (stream corto / skip).
