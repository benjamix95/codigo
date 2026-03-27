# Plan History Round 4 Remediation

Data: 2026-03-27
Area: `PlanPanel`, `PlanHistoryStore`, `ChatStore` rewind/checkpoint, chat deep-link plan attachment

## Bug Fix Record
- Categoria: A
- Bug: la selection della plan history restava globale e poteva contaminare thread o conversazioni diverse.
- Sintomo: aprendo il `PlanPanel` da una card plan in chat o riaprendo il panel, la preview poteva mostrare una history entry selezionata in un altro thread.
- Impatto: preview/build/download incoerenti, rischio di rebuild del contenuto sbagliato.
- Gravità: alta
- Steps to reproduce:
  1. selezionare una history entry in un thread
  2. aprire un altro thread compatibile
  3. aprire il `PlanPanel` o una card plan dalla chat
- Risultato attuale: la selection precedente poteva essere riusata fuori scope.
- Risultato atteso: la selection deve essere scoped per conversazione corrente.
- Causa probabile: uso residuo di `selectedEntryId` globale nei path `open/reset` del panel e nei deep-link dalla chat.
- Scope consentito: `PlanHistoryStore`, `PlanPanelView`, `ChatPanelView+PartB_ComposerUI`, `ChatPanelView+PartD_MessageCell`
- Non-scope: refactor strutturali del panel, cambi del modello `PlanHistoryEntry`
- Moduli confinanti da verificare: preview plan, build action, plan attachment open-in-panel
- Test aggiunti o aggiornati:
  - `PlanHistoryStoreTests.testScopedSelectionIsIndependentPerConversation`
  - `PlanHistoryStoreTests.testDeletingEntryClearsScopedSelectionForThatConversation`
  - `PlanPanelPreviewContentTests.testDisplayContentPrefersScopedHistoryWhenLiveBoardIsNotPreferred`
- Strategia di fix minimo: usare sempre selection scoped per la conversazione corrente nei path di open/reset e nel render della preview.
- Verifica post-fix: suite mirata `PlanHistoryStoreTests`, `PlanPanelPreviewContentTests`, `ChatStoreCheckpointTests`
- Commit previsto: `fix(plan): scope history selection and harden rewind restore`

## Bug Fix Record
- Categoria: A
- Bug: `rewindConversationState(...)` e `rewindConversationToMessageCount(...)` potevano lasciare un linked plan board stale dopo rewind.
- Sintomo: dopo rewind verso checkpoint senza linked snapshot, oppure verso `messageCount` che elimina tutti i checkpoint, il plan board linked poteva restare in memoria.
- Impatto: stato plan ripristinato in modo parziale, panel e build su board stale.
- Gravità: alta
- Steps to reproduce:
  1. creare checkpoint con `linkedPlanConversationId`
  2. mutare il linked plan board
  3. fare rewind verso checkpoint precedente o a `messageCount` senza checkpoint residui
- Risultato attuale: il linked board poteva sopravvivere anche se non era più valido per lo stato ripristinato.
- Risultato atteso: tutti i linked board rimossi dal rewind devono essere puliti, salvo quello esplicitamente preservato dal checkpoint finale.
- Causa probabile: il rewind ripristinava solo il board principale e il linked board del checkpoint target, senza rimuovere i linked board rimasti orfani.
- Scope consentito: `ChatStoreCheckpoints`
- Non-scope: redesign del sistema checkpoint
- Moduli confinanti da verificare: restore checkpoint, restore message-count rewind, plan panel trace/build dopo rewind
- Test aggiunti o aggiornati:
  - `ChatStoreCheckpointTests.testRewindConversationStateClearsStaleLinkedPlanBoardWhenTargetCheckpointHasNoLinkedSnapshot`
  - `ChatStoreCheckpointTests.testRewindConversationToMessageCountClearsLinkedPlanBoardWhenNoCheckpointRemains`
- Strategia di fix minimo: calcolare gli id linked rimossi dal rewind e pulire i board orfani non preservati dal checkpoint finale.
- Verifica post-fix: suite mirata `ChatStoreCheckpointTests`
- Commit previsto: `fix(plan): scope history selection and harden rewind restore`

## Modifiche applicate
- `PlanHistoryStore` usa selection scoped per conversazione già introdotta nel round precedente e ora viene consumata correttamente dai call-site `open/reset`.
- `PlanChatCardView` deep-linka il panel impostando la selection nello scope della conversazione corrente, non in quello globale.
- `PlanPanel` usa una policy esplicita per scegliere tra history scoped e live board nel preview content.
- `ChatStoreCheckpoints` rimuove linked plan board stale durante rewind a checkpoint e rewind a message count.

## Verifica
Comando eseguito:

```bash
xcodebuild test -project '/Users/benjaminstoica/SoloCode/Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PlanHistoryStoreTests -only-testing:SoloCodeAppTests/PlanPanelPreviewContentTests -only-testing:SoloCodeAppTests/ChatStoreCheckpointTests
```

Esito:
- `22` test eseguiti
- `0` failure
- `0` unexpected

Nota:
- `xcodebuildmcp` non è esposto in questa sessione Codex, quindi la validazione è stata eseguita con `xcodebuild` diretto.
