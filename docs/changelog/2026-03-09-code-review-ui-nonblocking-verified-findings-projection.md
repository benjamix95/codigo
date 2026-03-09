# 2026-03-09 — Code review UI nonblocking verified findings projection

## Modifiche
- eliminato l'uso del getter bridge `snapshot.verifiedFindingsProjection` dai path UI critici del `TaskActivityStore`
- fatta derivare la projection del pannello review da snapshot embedded, cache in-memory o sync da snapshot, senza passare da shared state
- reso il summary del pannello chat indipendente dalle read di persistence/shared state
- ripulita la cache `verifiedFindingsEnvelopesBySession` quando una sessione review viene eliminata

## Test
- aggiunta regressione su `TaskActivityStore.ingestCodeReviewSnapshot` con stored envelope confliggente
- aggiunta regressione su `ReviewPanelChatMessageFactory.summary` con stored envelope confliggente

## Rischio controllato
- nessun cambiamento al contratto backend di `VerifiedFindingsService`
- fix confinato al layer app/UI per evitare ulteriori freeze sul main thread
