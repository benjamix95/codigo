# Changelog — 2026-03-27 — Deep analysis round 2 su Plan/Panel/PlanFlow/Chat/Todo

## Cosa e' stato fatto

- Eseguito un secondo audit tecnico dopo la remediation precedente.
- Cercati bug residui e colli di bottiglia non ancora risolti nel flow `Plan/Panel/PlanFlow/Chat/Todo`.
- Isolati 6 problemi con evidenze puntuali nel codice.

## Findings principali

- **2 P1**
  - possibile doppia applicazione degli eventi raw nei job pipeline
  - restore di stato non coerente per la build-agent conversation
- **4 P2**
  - doppio sync `set_plan_panel_visible`
  - refresh snapshot chat sovrapposti
  - trace del Plan Panel limitata globalmente prima dello scope
  - `ToolTraceStore` ancora costoso per append frequenti

## File prodotti

- `docs/bugs/ARCH-2026-03-27-plan-panel-planflow-chat-todo-deep-analysis-round2.md`
- `docs/changelog/2026-03-27-plan-panel-planflow-chat-todo-deep-analysis-round2.md`

## Note

- Nessuna modifica al codice di produzione in questo pass.
- Nessun test eseguito: aggiornamento limitato ad analisi e documentazione.
