# P1 — SemanticIndex: Full Persist su Ogni Aggiornamento Incrementale

**Data**: 2026-03-25
**Categoria**: B — Importante (performance)
**Scope**: Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Build.swift

---

## Bug

`SemanticIndex.persist()` serializza TUTTI i chunk dell'indice in JSONL e li scrive su disco. Viene chiamato dopo ogni `incrementalUpdate()` e `updateFile()`.

## File e righe

- `SemanticIndex+Build.swift:84` — dopo `buildIndex()`
- `SemanticIndex+Build.swift:108` — dopo `incrementalUpdate()`
- `SemanticIndex+Build.swift:123` — dopo `updateFile()`
- `SemanticIndex+Persistence.swift:15-32` — implementazione persist()

## Problema

Con il budget di 50K chunk, ogni modifica di un singolo file causa la riscrittura dell'intero indice. La serializzazione JSON + sort + write atomico è O(n) con n = totale chunk.

## Impatto

- I/O burst significativo su ogni file save
- Latenza percepibile nell'editor su codebase grandi
- Usura disco SSD inutile

## Fix proposto

Implementare persistence incrementale:
1. Append-only log per delta (chunk aggiunti/rimossi)
2. Compaction periodica (merge log → JSONL completo)
3. Oppure: persist solo dopo batch di cambiamenti, non dopo ogni singolo file
