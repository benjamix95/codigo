# Changelog — 2026-03-27 — Analisi bottlenecks Plan/Panel/PlanFlow/Chat/Todo

## Cosa è stato fatto

- Analizzato il percorso di attivazione del Plan dalla chat.
- Analizzati `PlanFlow`, `PlanPanel`, invalidazioni della timeline chat e sincronizzazione dei todo.
- Isolati i colli di bottiglia principali con priorità e riferimenti puntuali ai file.

## Findings principali

- **6 colli di bottiglia principali**
- **4 P1**
  - attivazione del Plan troppo seriale
  - invalidazione aggressiva della timeline chat
  - query todo con complessità elevata
  - persistenza todo troppo frequente
- **2 P2**
  - sincronizzazione duplicata tra `TodoStore` e `ChatStore`
  - rendering del `PlanPanel` troppo pesante durante streaming

## File prodotti

- `docs/bugs/ARCH-2026-03-27-plan-panel-planflow-chat-todo-bottlenecks.md`
- `docs/changelog/2026-03-27-plan-panel-planflow-chat-todo-bottlenecks.md`

## Note

- Nessuna modifica al codice di produzione.
- Nessun test eseguito: aggiornamento limitato a documentazione e analisi tecnica.
