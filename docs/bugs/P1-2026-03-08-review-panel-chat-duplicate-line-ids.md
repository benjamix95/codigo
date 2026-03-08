# P1 - Review panel chat con ID duplicati nelle righe strutturate

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: la review chat renderizza sezioni `metadata` e `findings` con `ForEach(..., id: \.self)` su array di `String`, quindi righe duplicate provenienti da output MCP/swarm generano ID non univoci.
- Sintomo: durante stream con righe ripetute come `mcp_tool_call: 1│import Foundation`, `3│## Bug Fix Record` o percorsi ripetuti, SwiftUI logga `the ID ... occurs multiple times within the collection, this will give undefined results!`; in cascata possono comparire warning `AttributeGraph`, `onChange ... multiple times per frame` e `Publishing changes from within view updates is not allowed`.
- Impatto: comportamento non deterministico del pannello review chat, perdita di stabilità nel rendering e possibile desync di autoscroll/espansione durante output ripetitivo.
- Gravità: alta lato stabilità UI del workflow review
- Steps to reproduce:
  1. Aprire il pannello Code Review e andare nella tab Chat.
  2. Iniettare o ricevere una risposta strutturata con righe duplicate in `metadata`, `findings` o `log`.
  3. Osservare la console SwiftUI durante il rendering della risposta.
  4. Verificare la comparsa dei warning `ForEach<Array<String>, String, ...>`.
- Risultato attuale: le righe duplicate condividono lo stesso identificatore logico e SwiftUI entra in comportamento indefinito.
- Risultato atteso: ogni riga visualizzata deve avere un ID stabile e univoco anche quando il contenuto testuale è identico; anche sezioni con lo stesso titolo devono mantenere ID distinti.
- Causa probabile: `ReviewPanelChatStructuredSectionsView.swift` usava `id: \.self` per `section.lines`; inoltre gli ID delle sezioni generate da `ReviewPanelChatStructuredContent.reviewRunLogSections(...)` dipendevano solo dal titolo e due file helper (`ReviewPanelChatAutoscroll.swift`, `ReviewPanelChatStructuredLogView.swift`) non erano registrati nel progetto Xcode, indebolendo la verifica del fix.
- Scope consentito: parser/presentation del review panel chat, file registration nel progetto Xcode, test unitari review chat, docs bug/changelog.
- Non-scope: main chat, pipeline eventi del motore, store di orchestrazione, task activity panel globale.
- Moduli confinanti da verificare: `ReviewPanelChatStructuredContent.swift`, `ReviewPanelChatStructuredSectionsView.swift`, `ReviewPanelChatStructuredLogView.swift`, `ReviewPanelChatAutoscroll.swift`, test review chat.
- Test da aggiungere o aggiornare: regressione su ID univoci delle righe duplicate e su ID univoci delle sezioni con header ripetuti; smoke su fingerprint autoscroll.
- Strategia di fix minimo: introdurre un modello `displayLines` con ID derivati da `section.id + index`, riusarlo in tutte le view del review chat che renderizzano linee strutturate, rendere univoci gli ID sezione del parser e aggiungere al `.xcodeproj` solo i file review-chat mancanti necessari a build e test.
- Verifica post-fix:
  1. Eseguire `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelChatStructuredContentTests -only-testing:SoloCodeAppTests/ReviewPanelChatAutoscrollTests`.
  2. Verificare che `ReviewPanelChatStructuredContentTests` copra righe duplicate e header ripetuti.
  3. Verificare che `ReviewPanelChatAutoscrollTests` continui a passare dopo l’introduzione degli ID derivati.
- Commit previsto: `fix(review-chat): prevent duplicate structured line ids`
