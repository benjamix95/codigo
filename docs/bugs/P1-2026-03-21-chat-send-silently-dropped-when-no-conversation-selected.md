# P1 - Il submit della chat veniva scartato in silenzio senza conversazione selezionata

## Bug Fix Record
- Priorità: P1
- Categoria: A - Critico
- Bug: `sendMessage()` assumeva sempre una conversazione selezionata; quando `selectedConversationId` era `nil`, il submit del composer veniva scartato senza creare una thread target e senza mostrare feedback visibile.
- Sintomo:
  - premendo `Enter` o il bottone `Invia` non succedeva nulla di osservabile
  - il testo restava nel composer o l'utente percepiva un no-op totale
  - il problema emergeva quando la main chat era visibile ma non esisteva una conversazione attiva valida
- Impatto: rottura del flusso core di invio chat; impossibilità di iniziare una nuova conversazione da composer in alcuni stati UI.
- Gravità: alta
- Steps to reproduce:
  1. Portare la main chat in uno stato con `selectedConversationId == nil`.
  2. Digitare un prompt nel composer.
  3. Premere `Return` o cliccare `Invia`.
  4. Osservare che l'invio non produce messaggi ne' errori visibili.
- Risultato attuale: `sendMessage()` faceva `guard let targetConversationId = conversationId else { ... return }`; il messaggio tecnico veniva poi scritto `in: nil`, quindi spariva.
- Risultato atteso: se non esiste una conversazione selezionata, l'invio deve riusare una conversazione vuota compatibile col contesto oppure crearne una nuova e selezionarla prima di continuare.
- Causa probabile:
  - dipendenza implicita dalla selezione iniziale della conversazione
  - assenza di fallback locale nel percorso di submit del composer
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_SendMessage.swift`
  - `Tests/SoloCodeAppTests/ChatPanelBuildBehaviorTests.swift`
  - documentazione bug/changelog
- Non-scope:
  - refactor della selezione conversazioni lato `ContentView`
  - modifiche alla pipeline provider/runtime oltre la risoluzione della conversazione target
  - redesign del composer
- Moduli confinanti da verificare:
  - reuse di conversazioni vuote
  - creazione nuova conversazione sul contesto attivo
  - submit normale con conversazione gia` selezionata
- Test da aggiungere o aggiornare:
  - risoluzione target quando una conversazione e` gia` selezionata
  - preferenza per conversazione vuota riusabile
  - creazione nuova conversazione coerente con `EffectiveContext`
- Strategia di fix minimo:
  - introdurre una piccola risoluzione del target di invio
  - riusare una conversazione vuota compatibile, altrimenti crearne una nuova
  - aggiornare `selectedConversationId` solo quando serve
- Verifica post-fix:
  - test mirati su `resolveSendTargetConversation(...)`
  - regressione composer ancora verde
  - smoke manuale consigliato: aprire chat senza thread attiva e inviare subito dal composer
- Commit previsto: `fix(chat): create send target conversation when selection is missing`
