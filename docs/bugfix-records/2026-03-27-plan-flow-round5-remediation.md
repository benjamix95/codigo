# Plan Flow Round 5 Remediation

Data: 2026-03-27
Area: `PlanPanel`, `PlanHistoryStore`, `ChatStorePlans`

## Bug Fix Record
- Categoria: A
- Bug: il `Build` del `PlanPanel` continuava a usare il live board anche quando l’utente aveva selezionato una history entry.
- Sintomo: preview e download mostravano il piano storico selezionato, ma `Build` rilanciava il piano live corrente.
- Impatto: esecuzione del piano sbagliato, divergenza tra UI e runtime.
- Gravità: alta
- Steps to reproduce:
  1. aprire il `PlanPanel` su una conversazione con live board già presente
  2. selezionare una history entry differente con `chosenPath` buildabile
  3. premere `Build`
- Risultato attuale: il build partiva dal live board.
- Risultato atteso: il build deve rispettare la stessa precedence del preview.
- Causa probabile: `resolveBuildChoice()` privilegiava sempre `fallbackPlanBuildContent(...)` se il board live era non vuoto.
- Scope consentito: `PlanPanelView+HistoryHelpers.swift`, `PlanPanelView+Policy.swift`, test policy/preview
- Non-scope: refactor della UI del panel
- Moduli confinanti da verificare: preview panel, download, build button
- Test aggiunti o aggiornati:
  - `PlanPanelPreviewContentTests.testBuildChoicePrefersSelectedHistoryWhenLiveBoardIsNotPreferred`
  - `PlanPanelPreviewContentTests.testBuildChoiceDoesNotFallBackToLiveBoardWhenSelectedHistoryIsUnbuildable`
- Strategia di fix minimo: centralizzare una policy pura per il build choice e riusarla nel panel.
- Verifica post-fix: suite mirata `PlanPanelPreviewContentTests`
- Commit previsto: `fix(plan): align history selection and board sync`

## Bug Fix Record
- Categoria: A
- Bug: la selection di history cross-thread veniva mostrata come valida nella lista ma poi scartata dal resolver quando il thread non aveva context esplicito.
- Sintomo: l’utente poteva selezionare una entry visibile nella history section, ma preview/build ricadevano su altro contenuto.
- Impatto: selection apparentemente accettata ma semanticamente ignorata.
- Gravità: alta
- Steps to reproduce:
  1. aprire un thread senza `contextId/contextFolderPath`
  2. mostrare history entry di conversazioni sorelle nello stesso thread root
  3. selezionarne una dal panel
- Risultato attuale: la selection veniva invalidata dopo il click.
- Risultato atteso: se la entry è visibile e thread-compatible, deve restare selezionabile.
- Causa probabile: mismatch tra `isPlanHistoryEntryCompatibleWithCurrentThread` e `isPlanHistoryEntryCompatibleWithCurrentContext`.
- Scope consentito: `PlanPanelView+Policy.swift`
- Non-scope: refactor della lista history
- Moduli confinanti da verificare: preview content, history selection, download
- Test aggiunti o aggiornati:
  - `PlanPanelWorkspacePolicyTests.testNoContextHistoryCompatibilityAllowsSiblingConversationEntries`
- Strategia di fix minimo: rendere il path “no explicit context” compatibile con la policy thread-based già usata dalla lista.
- Verifica post-fix: suite mirata `PlanPanelWorkspacePolicyTests`
- Commit previsto: `fix(plan): align history selection and board sync`

## Bug Fix Record
- Categoria: A
- Bug: `planBoardDidPersist` aggiornava la history entry sbagliata nelle conversazioni con più snapshot e sincronizzava solo il markdown.
- Sintomo: più entry della stessa conversazione potevano divergere; il board persistito finiva sulla snapshot storica sbagliata o lasciava `chosenPath/options/title` stale.
- Impatto: history corrotta, preview incoerenti, rebuildability errata.
- Gravità: alta
- Steps to reproduce:
  1. creare più history entry per la stessa conversazione
  2. selezionare una entry o lasciare l’ultima come attiva
  3. persistere un nuovo `PlanBoard`
- Risultato attuale: aggiornamento della prima entry trovata per `conversationId`, con sync parziale.
- Risultato atteso: aggiornare l’entry attiva della conversazione, oppure la più recente, sincronizzando anche `title`, `options` e `chosenPath`.
- Causa probabile: matching per `firstIndex(where: conversationId)` e update limitato a `markdown`.
- Scope consentito: `PlanHistoryStore.swift`
- Non-scope: redesign completo del modello history
- Moduli confinanti da verificare: plan file writer, history preview, build from history
- Test aggiunti o aggiornati:
  - `PlanHistoryStorePersistenceTests.testBoardPersistedUpdatesLatestEntryForConversation`
  - `PlanHistoryStorePersistenceTests.testBoardPersistedPrefersSelectedEntryWhenConversationHasMultipleSnapshots`
- Strategia di fix minimo: usare priorità `selected entry -> latest entry` e sincronizzare i campi osservabili del panel.
- Verifica post-fix: suite mirata `PlanHistoryStorePersistenceTests`
- Commit previsto: `fix(plan): align history selection and board sync`

## Bug Fix Record
- Categoria: B
- Bug: il backfill startup di plan attachments creava side effect sulla selection e duplicava entry legacy quando `sourceMessageId` mancava.
- Sintomo: dopo bootstrap alcune conversazioni risultavano auto-selezionate; in presenza di entry legacy equivalenti venivano creati duplicati.
- Impatto: stato UI inatteso e history rumorosa.
- Gravità: media
- Steps to reproduce:
  1. bootstrap su conversazioni con assistant message pianificati
  2. presenza di entry legacy con stesso markdown ma `sourceMessageId == nil`
  3. esecuzione di `backfillPlanAttachmentsIfNeeded(...)`
- Risultato attuale: nuova entry creata con selection implicita e mancato riuso della legacy.
- Risultato atteso: riuso hash-based della entry legacy e nessuna mutazione della selection utente.
- Causa probabile: `createEntry(...)` selezionava sempre l’entry e il fallback `existingByHash` richiedeva ancora `sourceMessageId == msg.id`.
- Scope consentito: `PlanHistoryStore+Mutations.swift`, `ChatStorePlans.swift`
- Non-scope: migrazione storage completa
- Moduli confinanti da verificare: startup bootstrap, chat attachments, history count
- Test aggiunti o aggiornati:
  - `ChatStorePlanAttachmentTests.testBackfillReusesLegacyHashMatchWithoutSelectingConversation`
- Strategia di fix minimo: introdurre `selectForConversation` su `createEntry(...)` e rendere il fallback hash-based compatibile con legacy `sourceMessageId == nil`.
- Verifica post-fix: suite mirata `ChatStorePlanAttachmentTests`
- Commit previsto: `fix(plan): align history selection and board sync`

## Verifica
Comando eseguito:

```bash
xcodebuild test -project '/Users/benjaminstoica/SoloCode/Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PlanPanelPreviewContentTests -only-testing:SoloCodeAppTests/PlanPanelWorkspacePolicyTests -only-testing:SoloCodeAppTests/PlanHistoryStorePersistenceTests -only-testing:SoloCodeAppTests/ChatStorePlanAttachmentTests
```

Esito:
- `42` test eseguiti
- `0` failure
- `0` unexpected

Nota:
- `xcodebuildmcp` non è esposto in questa sessione, quindi la validazione è stata eseguita con `xcodebuild` diretto.
