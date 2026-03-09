# 2026-03-09 — Main chat adapter per VerifiedFindings

## Obiettivo
Far sì che i `reviewFinding` emessi dalla pipeline generale non restino solo messaggi, ma alimentino una sessione review condivisa per conversazione usando il backend `VerifiedFindings`.

## Modifiche implementate
- aggiunto `PipelineIntegrationService+VerifiedFindingsReview.swift`
- ogni `reviewFinding` nel runtime generale ora:
  - crea o aggiorna una sessione `inline-review-<conversationId>`
  - costruisce un `CodeReviewFinding` sintetico ma persistito
  - sincronizza l’envelope `VerifiedFindings` con `entryPoint = .mainChat`
  - pubblica la snapshot nel `TaskActivityStore`
- aggiunta inferenza base di `origin` e `category` per distinguere meglio finding `bug` e `security` nel path main chat

## Test eseguiti
- nuovo test app-level:
  - `SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests`
- eseguito insieme alla suite mirata `CoderEngineTests/VerifiedFindings*`
- risultato finale: test verdi

## Impatto
- la main chat ora ha un entrypoint reale verso la stessa source of truth usata da panel e review chat
- il dominio `security` comincia a essere visibile anche nel path main chat, almeno per finding review/event-driven
