# 2026-03-09 — Security gate quantitativo e rollout main chat

## Obiettivo
Chiudere due gap rimasti nel rollout `VerifiedFindings`:
- gate quantitativo per lo sblocco del dominio `Security`
- persistenza dei finding della main chat nello stesso backend shared

## Modifiche implementate

### Security gate quantitativo
- aggiunto `VerifiedFindingsSecurityGateService`
- il report valuta in modo quantitativo:
  - mismatch canonical/projection
  - duplicate non rilevati
  - finding verified senza evidence
  - finding verified senza verification report
  - copertura rollback sui patch artifact bug
  - apply+revalidate success rate
- il gate è ora esposto in:
  - `review_status`
  - `bughunter_status`
  - summary chat del review panel

### Stato `fixed_verified` derivato dal core
- la sync del core ora promuove automaticamente un finding a:
  - `fixed_verified` se patch applicata + validation passata
  - `fix_failed` se patch applicata ma validation fallita
  - `rollback_applied` se la patch viene marcata come rollback

### Main chat -> core shared
- aggiunto adapter `PipelineIntegrationService+VerifiedFindingsReview`
- un `reviewFinding` emesso dal runtime generale crea o aggiorna:
  - una sessione review sintetica per conversazione
  - una snapshot sincronizzata con envelope `VerifiedFindings`
- la main chat non lascia più questi finding solo nel layer messaggi

## Test eseguiti
- `CoderEngineTests/VerifiedFindingsSecurityGateServiceTests`
- `SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests`
- rieseguita la suite mirata `VerifiedFindings*`

## Risultato
- test mirati verdi
- panel, review chat, main chat e BugHunter leggono più chiaramente lo stesso stato condiviso
