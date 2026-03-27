# Deep Analysis Round 4 — Plan History / Checkpoints / Rewind / Live Board

**Data**: 2026-03-27
**Scope**: quarto audit tecnico sui flussi residui `PlanHistoryStore`, `ChatStoreCheckpoints`, `rewind`, `history/build selection`, `plan attachments`
**Tipo**: analisi read-only, nessuna modifica runtime applicata in questo pass

---

## Executive summary

Dopo i tre round precedenti, i problemi residui più rilevanti si concentrano su:

1. **divergenza tra history e live board**
2. **checkpoint/rewind che non ripristinano tutto il contesto UI**
3. **selection history globale che può sporcarsi tra contesti/thread**
4. **backfill attachment/history che può creare accoppiamenti fragili**

Non sono i path più “caldi”, ma sono i più rischiosi per regressioni UX e perdita di fiducia nello stato del panel.

---

## BOTTLENECK-R4-01 — `selectedEntryId` globale può trascinare stato tra contesti diversi

**Priorità**: P1
**Tipo**: bug logico / state leakage
**File**:
- `App/SoloCodeApp/Sources/Planning/PlanHistoryStore.swift`
- `App/SoloCodeApp/Sources/Planning/PlanHistoryStore+Queries.swift`
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+HistoryHelpers.swift`
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+Content.swift`

**Evidenza**
- `PlanHistoryStore` mantiene un unico `selectedEntryId` globale, non scoped per conversazione o contesto in [PlanHistoryStore.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Planning/PlanHistoryStore.swift#L6).
- `setSelectedEntry(id:)` scrive direttamente questo stato globale in [PlanHistoryStore+Queries.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Planning/PlanHistoryStore+Queries.swift#L47).
- `selectedHistoryEntryForConversation()` cerca poi di “filtrare a valle” la selection usando contesto/thread in [PlanPanelView+HistoryHelpers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+HistoryHelpers.swift#L41).
- `PlanPanelView+Content` usa comunque `planHistoryStore.selectedEntryId` nel `.id(...)` del workspace in [PlanPanelView+Content.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+Content.swift#L158).

**Problema**
- La selection vera è globale, mentre la compatibilità è locale. Quindi la UI di un thread può essere influenzata da una selezione fatta altrove anche se poi quella entry non è compatibile per il thread corrente.

**Impatto**
- refresh/identity del workspace non strettamente locale
- rischio di preview stale o flicker dopo switch contesto/thread
- comportamento difficile da ragionare e testare

**Direzione fix**
- introdurre `selectedEntryIdByContext` o `selectedEntryIdByConversation`
- evitare che componenti locali dipendano dall’ID globale se la selection non è valida per quel thread

---

## BOTTLENECK-R4-02 — Rewind ripristina chat e board, ma non riallinea la history selection del panel

**Priorità**: P1
**Tipo**: bug di stato / UX inconsistente
**File**:
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartR_Rewind.swift`
- `App/SoloCodeApp/Sources/Services/ChatStore/Checkpoints/ChatStoreCheckpoints.swift`
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+HistorySection.swift`

**Evidenza**
- `rewindConversation()` e `rewindToMessage(...)` resettano `planningState`, `planFlowPhase`, swarm state e build conversation IDs in [ChatPanelView+PartR_Rewind.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartR_Rewind.swift#L68) e [ChatPanelView+PartR_Rewind.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartR_Rewind.swift#L194).
- `ChatStoreCheckpoints` ripristina `planBoardSnapshot` e `linkedPlanBoardSnapshot`, ma non c’è nessun collegamento con `PlanHistoryStore.selectedEntryId` in [ChatStoreCheckpoints.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStore/Checkpoints/ChatStoreCheckpoints.swift#L50).
- La selection nel panel resta gestita a parte in [PlanPanelView+HistorySection.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+HistorySection.swift#L53).

**Problema**
- Dopo un rewind, il board può essere correttamente riportato indietro ma il panel history può restare selezionato su un’entry non più coerente con il board ripristinato.

**Impatto**
- mismatch tra contenuto live del panel e selection history evidenziata
- rischio di rebuild/preview da entry non più allineata allo stato ripristinato

**Direzione fix**
- al rewind, invalidare esplicitamente la selection history o riallinearla all’entry/board corrispondente
- legare la selection del panel a uno snapshot/checkpoint compatibile, non solo al click precedente

---

## BOTTLENECK-R4-03 — `rewindConversationToMessageCount` usa l’ultimo checkpoint <= messageCount, ma può lasciare board stale quando non esiste checkpoint adatto

**Priorità**: P2
**Tipo**: bug edge case
**File**:
- `App/SoloCodeApp/Sources/Services/ChatStore/Checkpoints/ChatStoreCheckpoints.swift`

**Evidenza**
- In `rewindConversationToMessageCount`, se esiste un `lastCheckpoint`, viene ripristinato il board relativo; altrimenti rimuove solo `planBoards[conversationId]` in [ChatStoreCheckpoints.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStore/Checkpoints/ChatStoreCheckpoints.swift#L98).
- Il ramo `else` senza checkpoint pulisce il board della conversazione principale, ma non tratta un eventuale `linkedPlanConversationId` esterno già esistente nello stato corrente.

**Problema**
- In assenza di un checkpoint utile, la conversazione linked plan può restare con board stale rispetto al rewind della conversazione agent.

**Impatto**
- possibili ghost state nella plan conversation linked
- rewind apparentemente riuscito sulla chat, ma panel plan non riallineato

**Direzione fix**
- quando non esiste checkpoint applicabile, pulire anche l’eventuale linked plan state associato al flow corrente
- oppure persistere esplicitamente il mapping conversation -> linked plan conversation nel checkpoint model/read path

---

## BOTTLENECK-R4-04 — `backfillPlanAttachmentsIfNeeded` si basa su matching opportunistico e può accoppiare history entry non canoniche

**Priorità**: P2
**Tipo**: bug di matching / data hygiene
**File**:
- `App/SoloCodeApp/Sources/Services/ChatStore/Plans/ChatStorePlans.swift`

**Evidenza**
- `backfillPlanAttachmentsIfNeeded(historyStore:)` cerca prima l’entry per `conversationId`, poi per hash del markdown in [ChatStorePlans.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStore/Plans/ChatStorePlans.swift#L68).
- Se non trova nulla crea una nuova entry e attacca `historyEntryId` ai messaggi.

**Problema**
- Il matching per hash/heuristic è utile per la migrazione, ma su dati già sporchi o duplicati può legare il messaggio a un’entry “compatibile” ma non realmente canonica per il thread corrente.

**Impatto**
- attachment/history card potenzialmente sbagliata
- più difficile capire quale entry è la sorgente vera del plan allegato

**Direzione fix**
- salvare un legame stabile `historyEntryId` / `sourceMessageId` già in fase di creazione del plan
- relegare il matching per hash a una sola migrazione one-shot con marcatura esplicita

---

## BOTTLENECK-R4-05 — `entriesForContext` e compatibilità thread sono controlli separati, quindi il filtering history è distribuito e fragile

**Priorità**: P2
**Tipo**: design smell / maintenance bottleneck
**File**:
- `App/SoloCodeApp/Sources/Planning/PlanHistoryStore+Queries.swift`
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+HistorySection.swift`
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+HistoryHelpers.swift`

**Evidenza**
- `entriesForContext` filtra per context/folder in [PlanHistoryStore+Queries.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Planning/PlanHistoryStore+Queries.swift#L65).
- `HistorySection` applica poi un secondo filtro per thread root con `isPlanHistoryEntryAllowedForCurrentConversationThread` in [PlanPanelView+HistorySection.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+HistorySection.swift#L8).
- `selectedHistoryEntryForConversation()` ripete ancora una validazione simile in [PlanPanelView+HistoryHelpers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+HistoryHelpers.swift#L41).

**Problema**
- La stessa nozione di “entry history valida qui” è spezzata in tre posti.

**Impatto**
- rischio di drift tra lista renderizzata, entry selezionata e preview/build content
- alta fragilità quando si cambia una sola regola di compatibilità

**Direzione fix**
- centralizzare in un solo helper/query “entries visible for current thread context”
- far usare quel risultato sia alla lista sia alla selection sia al preview/build path

---

## BOTTLENECK-R4-06 — `PlanPanel` continua a usare `latestPlanHistoryEntry()` come fallback di preview/download anche quando il live board è la source of truth

**Priorità**: P2
**Tipo**: ambiguità di source-of-truth
**File**:
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+Content.swift`
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+HistoryHelpers.swift`

**Evidenza**
- `displayPlanContent` può preferire `latestPlanHistoryEntry()` se `shouldPreferLivePlanBoardOverHistory(...)` è falso in [PlanPanelView+Content.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+Content.swift#L40).
- `downloadCurrentPlan()` fa fallback a `latestPlanHistoryEntry()` prima del board corrente in [PlanPanelView+HistoryHelpers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+HistoryHelpers.swift#L135).

**Problema**
- Nei casi limite di board già mutato e history non ancora aggiornata, preview e download possono attingere a sorgenti diverse.

**Impatto**
- contenuto mostrato/scaricato non sempre coerente con lo stato operativo attuale

**Direzione fix**
- definire una sola source of truth per:
  - preview live
  - build choice
  - download corrente
- usare la history solo come snapshot esplicito quando selezionata manualmente

---

## Riepilogo Priorità

| Priorità | ID | Area | Impatto principale |
|----------|----|------|--------------------|
| P1 | BOTTLENECK-R4-01 | history selection globale | state leakage tra contesti |
| P1 | BOTTLENECK-R4-02 | rewind vs history selection | panel incoerente dopo rewind |
| P2 | BOTTLENECK-R4-03 | rewind senza checkpoint utile | linked plan stale |
| P2 | BOTTLENECK-R4-04 | attachment backfill | accoppiamento history fragile |
| P2 | BOTTLENECK-R4-05 | filtering history distribuito | drift logico e manutenzione |
| P2 | BOTTLENECK-R4-06 | preview/download source-of-truth | ambiguità tra live board e history |

---

## Ordine consigliato di intervento

1. rendere locale/scoped la history selection
2. riallineare rewind + selection del panel
3. consolidare la query di visibility history in un solo punto
4. ridurre il ruolo del matching opportunistico nel backfill attachment
5. unificare source-of-truth tra live board, preview e download
