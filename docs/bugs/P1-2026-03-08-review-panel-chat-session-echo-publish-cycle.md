# P1 - Echo sincrono del session store review panel durante update SwiftUI

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: il `CodeReviewPanelStore` persiste lo stato chat nel `ReviewPanelChatSessionStore`, che ripubblica subito `conversationsByKey`; il `sink` del pannello riapplica la stessa conversazione nello stesso turno di update SwiftUI.
- Sintomo: warning runtime `Publishing changes from within view updates is not allowed, this will cause undefined behavior.` accompagnato da cicli `AttributeGraph` quando il pannello review riceve eventi live o aggiorna la chat.
- Impatto: il pannello chat review può entrare in un ciclo di publish reentranti mentre la view è in render, con rischio di UI instabile e aggiornamenti duplicati dei metadati thread.
- Gravità: alta lato affidabilità UI del pannello review.
- Steps to reproduce:
  1. Aprire il pannello Code Review e avviare una review o una chat che aggiorna `chatMessages` in streaming.
  2. Lasciare che il pannello persista i messaggi nel `ReviewPanelChatSessionStore`.
  3. Osservare la console runtime di Xcode durante gli update rapidi della chat.
- Risultato attuale: il mirror `chatThreads`/`activeChatThreadId` viene riapplicato sincronicamente dal `sink` del session store mentre SwiftUI sta ancora aggiornando la view.
- Risultato atteso: il pannello deve applicare il mirror della conversazione solo nel tick successivo del main actor, fuori dal ciclo di update in corso.
- Causa probabile: re-entrancy sincrona tra `persistChatState()` e il `sink` su `$conversationsByKey`.
- Scope consentito: `CodeReviewPanelStore.swift`, test dedicato del review panel, documentazione bug/changelog.
- Non-scope: refactor del session store, redesign del pannello review, modifiche ai reducer di task activity.
- Moduli confinanti da verificare: persistenza thread chat review, sottotitoli dei thread, stream review/chat del pannello.
- Test da aggiungere o aggiornare: regressione che verifica che il mirror `chatThreads` non venga riscritto sincronicamente subito dopo `appendChatMessage`.
- Strategia di fix minimo: cancellare eventuali apply pendenti e differire l’`applyChatConversationState` del `sink` con `Task.yield()`.
- Verifica post-fix:
  1. Eseguire il test `CodeReviewPanelChatStateDeferralTests`.
  2. Eseguire smoke test del lifecycle review panel correlato.
  3. Verificare in console l’assenza dei warning SwiftUI/AttributeGraph nel flusso review chat.
- Commit previsto: `fix(review): defer chat session echo outside swiftui updates`
