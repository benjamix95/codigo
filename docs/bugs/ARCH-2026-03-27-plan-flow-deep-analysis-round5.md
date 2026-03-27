# Deep Analysis Round 5

Data: 2026-03-27
Area: `PlanPanel`, `PlanHistoryStore`, `ChatStorePlans`, `startup/bootstrap`
Stato: analisi soltanto

## Contesto
Dopo i fix dei round precedenti restano alcuni bug di correttezza nel flusso `history / live board / attachment / rewind`. In questo pass il focus non è stato sulle performance ma sulle inconsistenze tra ciò che il panel mostra, ciò che il build usa davvero e ciò che il bootstrap ripristina.

## Finding

### P1 — `Build` ignora ancora la history selezionata se esiste un live board
- Bug: il panel può mostrare o scaricare una history entry selezionata, ma `Build` continua a usare il live board quasi sempre.
- Sintomo: selezionando una entry storica nel panel, il contenuto visibile cambia, ma premendo `Build` viene eseguito il piano live corrente.
- Impatto: l’utente crede di rebuildare una history entry e invece rilancia il piano live. È un bug di correttezza del flusso, non solo UX.
- Causa probabile: [resolveBuildChoice()](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+HistoryHelpers.swift#L87) ritorna sempre il risultato di `fallbackPlanBuildContent(...)` se il live board ha `goal`, `steps` o `chosenPath`, senza rispettare davvero `shouldPreferLivePlanBoardOverHistory`. Il preview invece usa una precedence diversa in [PlanPanelView+Content.swift](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+Content.swift#L23).
- Evidenza:
  - [PlanPanelView+HistoryHelpers.swift#L87](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+HistoryHelpers.swift#L87)
  - [PlanPanelView+Content.swift#L23](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+Content.swift#L23)
- Effetto collaterale: `preview/download` e `build` non condividono la stessa source-of-truth.

### P1 — `planBoardDidPersist` aggiorna la history entry sbagliata quando una conversazione ha più snapshot
- Bug: il sync `plan board -> history` sceglie la prima entry della conversazione, non quella più recente o quella attiva.
- Sintomo: dopo più generazioni/rebuild nella stessa conversazione, il board persistito può finire sulla snapshot storica sbagliata.
- Impatto: corruzione silenziosa della history, preview incoerenti e file `.solocode/plan/*.md` riscritti con contenuti non corrispondenti all’entry giusta.
- Causa probabile: [handleBoardPersisted](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Planning\/PlanHistoryStore.swift#L53) usa `firstIndex(where: { $0.conversationId == convId })`, mentre le entry vengono aggiunte in coda in [PlanHistoryStore+Mutations.swift#L34](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Planning\/PlanHistoryStore+Mutations.swift#L34). Quindi la “prima” entry non è necessariamente la più recente né la selezionata.
- Evidenza:
  - [PlanHistoryStore.swift#L53](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Planning\/PlanHistoryStore.swift#L53)
  - [PlanHistoryStore+Mutations.swift#L34](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Planning\/PlanHistoryStore+Mutations.swift#L34)
- Nota: i test esistenti in [PlanHistoryStorePersistenceTests.swift](\/Users\/benjaminstoica\/SoloCode\/Tests\/SoloCodeAppTests\/PlanHistoryStorePersistenceTests.swift) non coprono questo caso multi-entry.

### P1 — Nel thread senza context esplicito la history section permette selezioni che il resolver poi rifiuta
- Bug: la lista history ammette entry di conversazioni sorelle nello stesso thread root, ma la selection corrente le invalida subito se `contextId/contextFolderPath` sono nil.
- Sintomo: l’utente può cliccare `Preview` o `Selected` su una entry visibile nella lista, ma il panel poi ricade sulla prima entry visibile o sul live board.
- Impatto: selection apparentemente accettata ma semanticamente ignorata; build/download possono usare un’altra entry rispetto a quella scelta.
- Causa probabile:
  - la lista usa thread compatibility in [PlanPanelView+HistoryHelpers.swift#L5](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+HistoryHelpers.swift#L5) e [PlanPanelView+HistoryHelpers.swift#L19](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+HistoryHelpers.swift#L19)
  - la selection usa invece `isPlanHistoryEntryCompatibleWithCurrentContext(...)`, che quando non esiste context richiede `entry.conversationId == currentConversationId` in [PlanPanelView+Policy.swift#L107](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+Policy.swift#L107)
  - il click nella lista salva davvero la selection scoped in [PlanPanelView+HistorySection.swift#L125](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+HistorySection.swift#L125), ma [selectedHistoryEntryForConversation()](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+HistoryHelpers.swift#L51) la filtra via.
- Evidenza:
  - [PlanPanelView+HistoryHelpers.swift#L5](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+HistoryHelpers.swift#L5)
  - [PlanPanelView+Policy.swift#L107](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+Policy.swift#L107)
  - [PlanPanelView+HistorySection.swift#L125](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+HistorySection.swift#L125)
  - [PlanPanelView+HistoryHelpers.swift#L51](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+HistoryHelpers.swift#L51)

### P2 — Il bootstrap attachment/history muta la selection utente in background
- Bug: il bootstrap deferred crea entry history e le marca automaticamente come selezionate, anche se l’utente non ha mai aperto il panel.
- Sintomo: dopo startup o migrazione, alcune conversazioni possono aprire il panel già “puntato” su una history entry creata dal backfill.
- Impatto: stato UI non intenzionale, con possibile precedence non ovvia tra history auto-selezionata e live board.
- Causa probabile:
  - il bootstrap chiama [backfillPlanAttachmentsIfNeeded(...)](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/App\/Bootstrap\/Sections\/SoloCodeApp+StartupBootstrapPhases.swift#L44)
  - il backfill crea entry via [ChatStorePlans.swift#L95](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Services\/ChatStore\/Plans\/ChatStorePlans.swift#L95)
  - `createEntry(...)` aggiorna sempre `selectedEntryIdByConversation` e `selectedEntryId` in [PlanHistoryStore+Mutations.swift#L36](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Planning\/PlanHistoryStore+Mutations.swift#L36)
- Evidenza:
  - [SoloCodeApp+StartupBootstrapPhases.swift#L44](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/App\/Bootstrap\/Sections\/SoloCodeApp+StartupBootstrapPhases.swift#L44)
  - [ChatStorePlans.swift#L95](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Services\/ChatStore\/Plans\/ChatStorePlans.swift#L95)
  - [PlanHistoryStore+Mutations.swift#L36](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Planning\/PlanHistoryStore+Mutations.swift#L36)

### P2 — La deduplica del backfill legacy è troppo stretta e può duplicare history entry
- Bug: il path “by hash” del backfill non funziona come fallback per i dati legacy se manca `sourceMessageId`.
- Sintomo: durante migrazioni/bootstrap si possono creare nuove history entry anche se ne esiste già una equivalente per lo stesso messaggio/piano.
- Impatto: duplicati in history, plan attachment agganciati a entry nuove invece di riusare quelle legacy, rumore nel panel.
- Causa probabile: il cosiddetto fallback `existingByHash` in [ChatStorePlans.swift#L84](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Services\/ChatStore\/Plans\/ChatStorePlans.swift#L84) richiede comunque `entry.sourceMessageId == msg.id`, quindi non copre davvero i casi legacy senza `sourceMessageId`.
- Evidenza:
  - [ChatStorePlans.swift#L80](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Services\/ChatStore\/Plans\/ChatStorePlans.swift#L80)
  - [ChatStorePlans.swift#L84](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Services\/ChatStore\/Plans\/ChatStorePlans.swift#L84)
  - [ChatStorePlanAttachmentTests.swift#L38](\/Users\/benjaminstoica\/SoloCode\/Tests\/SoloCodeAppTests\/ChatStorePlanAttachmentTests.swift#L38) copre solo l’idempotenza nel caso già moderno, non il bootstrap legacy con `sourceMessageId` assente.

### P2 — Anche quando `planBoardDidPersist` colpisce l’entry giusta, il sync resta parziale
- Bug: il sync board->history aggiorna solo `markdown`, lasciando `chosenPath`, `options` e metadati della entry potenzialmente stale.
- Sintomo: preview, option badge e buildabilità della history entry possono divergere dal board persistito più recente.
- Impatto: una entry può sembrare aggiornata in preview ma restare vecchia per `resolvedBuildContent(...)` o `selectedOptionIdForHistoryEntry(...)`.
- Causa probabile: [handleBoardPersisted](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Planning\/PlanHistoryStore.swift#L59) tocca solo `markdown` e `updatedAt`.
- Evidenza:
  - [PlanHistoryStore.swift#L59](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Planning\/PlanHistoryStore.swift#L59)
  - [PlanPanelView+HistoryHelpers.swift#L74](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+HistoryHelpers.swift#L74)
  - [PlanPanelView+HistoryHelpers.swift#L120](\/Users\/benjaminstoica\/SoloCode\/App\/SoloCodeApp\/Sources\/Panels\/PlanPanel\/PlanPanelView+HistoryHelpers.swift#L120)

## Ordine consigliato per il prossimo fix
1. allineare davvero `resolveBuildChoice()` alla stessa precedence del preview
2. correggere `planBoardDidPersist` per puntare all’entry attiva o più recente corretta
3. unificare il contratto tra “entry visibile nel thread” e “entry selezionabile davvero”
4. togliere gli effetti collaterali di selection dal bootstrap/backfill
5. rendere la deduplica del backfill legacy realmente hash-based quando `sourceMessageId` manca

## Rischi laterali
- `Build` e `Download` possono divergere ancora finché non condividono una stessa policy centrale.
- Ogni fix su `PlanHistoryStore` va coperto con test multi-entry, multi-thread-root e legacy migration, non solo con test “happy path”.
