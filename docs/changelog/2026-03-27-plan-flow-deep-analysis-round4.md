# Changelog — 2026-03-27 — Deep analysis round 4 su history/checkpoint/rewind

## Cosa e' stato fatto

- Eseguito un quarto audit tecnico sul flow `PlanHistoryStore`, `ChatStoreCheckpoints`, `rewind`, `history/build selection` e attachment backfill.
- Isolati 6 problemi residui con focus su consistenza di stato, non su puro hot path.

## Findings principali

- **2 P1**
  - selection history globale con leakage tra contesti/thread
  - rewind che non riallinea la selection del panel
- **4 P2**
  - rewind senza checkpoint utile può lasciare linked plan stale
  - backfill attachment/history con matching opportunistico fragile
  - visibility history distribuita su troppi punti
  - source of truth ambigua tra live board e history per preview/download

## File prodotti

- `docs/bugs/ARCH-2026-03-27-plan-flow-deep-analysis-round4.md`
- `docs/changelog/2026-03-27-plan-flow-deep-analysis-round4.md`

## Note

- Nessuna modifica runtime in questo pass.
- Nessun test eseguito: aggiornamento limitato ad analisi e documentazione.
