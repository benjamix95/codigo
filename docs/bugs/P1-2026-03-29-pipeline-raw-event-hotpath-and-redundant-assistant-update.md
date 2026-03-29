# P1 - Doppio fan-out raw pipeline e replace ridondanti di assistant_update

## Bug Fix Record
- Categoria: B - Importante
- Bug: `PipelineIntegrationService.handleRawEvent` continuava a inoltrare envelope/task activity anche quando un `rawEventHandler` esterno era già il proprietario del path; inoltre `assistant_update` poteva emettere `textReplace` ripetuti anche quando il testo visibile conteneva già il payload.
- Sintomo: duplicazione di attività nel pannello task/swarm, più mutazioni UI del necessario, extra lavoro nel reducer pipeline e nel bridge Rust durante stream con `assistant_update`.
- Impatto: maggiore fan-out su `TaskActivityStore`, più render e persistenze inutili, rumore nel trace della chat.
- Gravità: P1
- Steps to reproduce:
  1. eseguire una job pipeline con `rawEventHandler` esterno attivo
  2. inviare un raw event normalizzabile come `command_execution`
  3. osservare che il callback esterno riceve l’evento ma anche `TaskActivityStore` accumula una copia locale
  4. inviare più `assistant_update` con payload contenuto nel testo già visibile
  5. osservare replace ridondanti nel runtime pipeline
- Risultato attuale: fan-out duplicato e replace superflui
- Risultato atteso: il callback esterno possiede il path raw senza duplicazione locale; `assistant_update` emette replace solo quando il contenuto visibile cambia davvero
- Causa probabile: ramo `else` finale che inoltrava comunque gli envelope con callback esterno e confronto troppo debole nel path `assistant_update`
- Scope consentito: `PipelineIntegrationService+EventSupport.swift`, test pipeline correlati, helper già esistenti di promozione testo
- Non-scope: refactor di `TaskActivityStore`, `EventNormalizer`, `ChatPanelView`, persistence e orchestrator
- Moduli confinanti da verificare: raw stream main chat, reducer pipeline, `TaskActivityStore`, callback `handleRawStreamEvent`
- Test da aggiungere o aggiornare:
  - regressione su soppressione `TaskActivity` con callback raw esterno
  - regressione su deduplicazione `assistant_update`
- Strategia di fix minimo: eliminare solo il forward locale nel ramo con callback esterno e riusare la policy esistente `promotedAssistantUpdateContent`
- Verifica post-fix: suite mirata `PipelineIntegrationServiceTests` e controllo diff limitato ai file di scope
- Commit previsto: `fix(pipeline): suppress duplicate raw-event fan-out and redundant assistant updates`
