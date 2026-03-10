# 2026-03-10 — Hardening lock MCP, verified findings UI e review stream

## Modifiche
- rimosso il semaforo named dal path di produzione del lock shared-state MCP e ripristinato un acquisition path crash-safe basato su `flock(...)`
- introdotto un reserve FD dedicato per recuperare i casi `EMFILE/ENFILE` senza eseguire il body con lock non affidabili
- limitato il recovery di `verifiedFindingsEnvelope(...)` al solo stato in-memory nel path sincrono del `TaskActivityStore`
- bloccati anche gli update tardivi `textDelta` / `textReplace` dopo `finishPanelActionOutput(...)`
- aggiornati i test review panel e verified findings per coprire i nuovi edge case

## Test
- `CodeReviewPanelChatStateDeferralTests`
- `PipelineIntegrationVerifiedFindingsTests`
- suite lock MCP/BugHunter mirata

## Rischio controllato
- niente semafori named persistenti nel lock shared-state
- niente recovery persistita bloccante nel main actor del review panel
- transcript review immutabile anche per stream update tardivi
