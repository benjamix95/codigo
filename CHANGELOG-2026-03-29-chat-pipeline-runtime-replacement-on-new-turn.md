# Changelog

## 2026-03-29

### Fix
- corretto `PipelineIntegrationService.executeJob(...)` perché un nuovo job sulla stessa conversazione rimpiazzi il runtime pipeline precedente invece di uscire in silenzio
- eliminato il caso in cui il turno nuovo restava senza `PipelineConversationRuntime` e cadeva nel fallback `no_pipeline_turn` con interleaving degradato

### Test
- aggiunta regressione in `/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/PipelineIntegrationLifecycleTests.swift` che verifica la sostituzione del runtime e del relativo `assistantMessageId` quando due job partono sulla stessa conversazione
- rieseguiti test mirati su lifecycle pipeline, service pipeline e regressioni chat interleaving

### Evidenze
- dai log:
  - il runtime precedente restava attivo su `cb245932-31ec-443c-abe6-c443814ed8e3`
  - il turno nuovo `69a198d6-4de2-448c-9212-bcdab2ca0ff6` mostrava solo `merge_uses_synthetic_turn_from_tool_trace_events`
  - i due segnali comparivano nello stesso intervallo temporale sulla stessa conversazione `c2be5ca1-404d-4047-b0fc-98cc932eeb58`
