# 2026-03-09 — BugHunter surface allineata a VerifiedFindings

## Obiettivo
Allineare le read API di BugHunter alla nuova semantica `VerifiedFindings`, senza introdurre una seconda rappresentazione del dominio bug.

## Modifiche implementate
- `bughunter_status` ora espone anche:
  - `verified_findings`
  - `candidate_queue`
  - `duplicates`
  - `stale_candidates`
- `bughunter_findings` ora include metadati provenienti dalla projection canonica:
  - `domain`
  - `possible_duplicate_of`
  - `stale_status`

## Impatto
- la surface MCP di BugHunter riflette meglio il core shared
- i consumer chat/panel/tool vedono un output più coerente con candidate/verified/dedup

## Validazione
- incluso nella stessa esecuzione `xcodebuild test` del batch `VerifiedFindings` mirato
- nessun failure aggiuntivo rilevato
