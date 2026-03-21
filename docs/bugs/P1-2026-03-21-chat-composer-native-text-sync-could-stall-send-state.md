# P1 - Il composer poteva mostrare testo nativo senza aggiornare lo stato di invio SwiftUI

## Bug Fix Record
- Priorità: P1
- Categoria: A - Critico
- Bug: il `NSTextView` del composer poteva contenere testo visibile mentre `inputText` non risultava allineato in tempo al layer SwiftUI; in quel caso il bottone `Invia` restava disabilitato e il submit poteva partire con stato incompleto.
- Sintomo:
  - il testo era presente nel composer ma `Invia` restava inattivo o sembrava non reagire
  - `Return` e click sul bottone non producevano invio affidabile
  - il problema si manifestava come desincronizzazione tra testo nativo e stato SwiftUI
- Impatto: rottura del flusso core del composer; impossibilità di inviare anche con testo visibile nel campo.
- Gravità: alta
- Steps to reproduce:
  1. Digitare nel composer fino ad avere testo visibile nel `NSTextView`.
  2. Entrare in uno stato in cui il bridge AppKit/SwiftUI non sincronizza tempestivamente `inputText`.
  3. Premere `Return` o cliccare `Invia`.
  4. Osservare che il layer SwiftUI non considera il composer inviabile nonostante il testo visibile.
- Risultato attuale: la sync del testo dipendeva dal delegate `NSTextViewDelegate`; il submit non forzava un flush dell'ultimo snapshot del testo nativo.
- Risultato atteso: il composer deve propagare il testo nativo direttamente al binding SwiftUI e forzare il flush dell'ultimo snapshot prima del submit.
- Causa probabile:
  - dipendenza dal solo percorso delegate per l'aggiornamento di `inputText`
  - valutazione di `canSend` troppo stretta sul solo `isProviderReady`, che poteva lasciare il bottone apparentemente morto
- Scope consentito:
  - `App/SoloCodeApp/Sources/ChatView/Composer/ComposerTextView.swift`
  - `App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView+Attachments.swift`
  - `Tests/SoloCodeAppTests/ComposerTextViewFocusTests.swift`
  - documentazione bug/changelog
- Non-scope:
  - refactor del runtime di invio
  - redesign del composer
  - modifiche ai provider oltre la UX del bottone
- Moduli confinanti da verificare:
  - sync testo nativo -> binding
  - flush del testo prima del submit
  - focus/blur del composer
- Test da aggiungere o aggiornare:
  - callback diretto del testo nativo verso il binding
  - flush del testo piu` recente al momento di `Return`
- Strategia di fix minimo:
  - aggiungere callback dirette `onTextChange` e `onFocusChange` sul `ComposerNativeNSTextView`
  - sincronizzare il binding prima di invocare `onSubmit`
  - rendere cliccabile `Invia` anche quando il readiness provider e` in ritardo, delegando i controlli finali al runtime
- Verifica post-fix:
  - suite mirata del composer verde
  - smoke manuale consigliato: digitazione, click `Invia`, `Return`, provider non pronto con feedback visibile
- Commit previsto: `fix(chat): flush native composer text before submit`
