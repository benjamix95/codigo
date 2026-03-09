# 2026-03-09 — BugHunter lifecycle sul core shared e persisted verified findings

## Obiettivo
Avvicinare BugHunter al backend shared come motore operativo e dare a `VerifiedFindings` una persistenza separata nel shared state.

## Modifiche implementate

### BugHunter lifecycle
- aggiunto `bughunter_cancel_run`
- lo snapshot BugHunter ora memorizza anche:
  - `verifiedFindingsCount`
  - `candidateFindingsCount`
  - `lastRevalidationVerdict`
  - `securityGateReady`
- l’autofix BugHunter ora:
  - prepara patch
  - applica patch
  - rilancia `revalidate_finding`
  - tenta `rollback_patch` se la revalidation fallisce
- dopo ogni step patch BugHunter aggiorna il proprio snapshot dai dati canonici della review collegata

### Shared state separato
- aggiunto `MCPSharedState+VerifiedFindings.swift`
- l’envelope `VerifiedFindings` viene salvato anche in una directory separata:
  - `verified-findings/sessions/<sessionId>.json`
- la lettura della snapshot review può fare fallback a questo file se l’envelope annidato manca
- la delete della sessione review pulisce anche il file `VerifiedFindings` correlato

### Surface review esplicita
- aggiunto `review_close_finding`
- aggiunto supporto review esplicito a:
  - `revalidate_finding`
  - `rollback_patch`
  - `close_finding`

## Test eseguiti
- `BugHunterHandlerTests`
- `CodeReviewHandlerTests/testReviewRevalidateFindingQueuesCommand`
- `CodeReviewHandlerTests/testReviewRollbackPatchQueuesCommand`
- `CodeReviewHandlerTests/testReviewCloseFindingQueuesCommand`
- `VerifiedFindingsSharedStateTests`

## Impatto
- BugHunter è meno wrapper passivo e più consumer dello stato canonico
- lo shared state `VerifiedFindings` è persistito separatamente dalla sola snapshot review
- il workflow review espone ora anche la chiusura esplicita del finding
