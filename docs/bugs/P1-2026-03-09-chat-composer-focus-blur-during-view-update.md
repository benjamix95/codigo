# P1 - Composer chat perde focus o genera blur spurio durante l'update della view

## Bug Fix Record
- Priorità: P1
- Categoria: A - Critico
- Bug: il composer della chat poteva cambiare focus/blur mentre SwiftUI stava ancora aggiornando la view, causando warning di modifica stato durante il render e perdita non deterministica del focus dell'input.
- Sintomo:
  - il campo composer perdeva il focus subito dopo il mount o durante transizioni di stato rapide
  - potevano comparire warning/runtime issue legati a "state modification during view updates"
  - in alcuni casi il cursore non restava nel composer dopo auto-focus o blur programmato
- Impatto: regressione sul flusso core di input chat; UX instabile nell'inserimento messaggi e rischio di side effect su submit, shortcut tastiera e auto-focus del composer.
- Gravità: alta
- Steps to reproduce:
  1. Aprire la chat con auto-focus del composer attivo.
  2. Innescare un cambio rapido di stato che alterna `isFocused`, per esempio mount iniziale, cambio panel o reset del composer.
  3. Osservare che `updateNSView` tenta di chiamare `makeFirstResponder(...)` durante l'update della view.
  4. Verificare warning di runtime o perdita del focus/cursore nel composer.
- Risultato attuale: i cambi focus/blur venivano eseguiti in linea dentro `updateNSView`, con possibile collisione con il ciclo di aggiornamento SwiftUI/AppKit.
- Risultato atteso: il composer deve applicare focus e blur solo dopo il completamento del pass di update, mantenendo il focus coerente senza warning o perdita del cursore.
- Causa probabile:
  - `ComposerTextView.updateNSView(...)` chiamava `makeFirstResponder(...)` direttamente durante l'update
  - la sincronizzazione bidirezionale tra `isFocused` e delegate AppKit lasciava spazio a re-entry nel ciclo di rendering
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/ComposerTextView.swift`
  - documentazione bug/changelog
- Non-scope:
  - redesign del composer
  - refactor del bridge SwiftUI/AppKit oltre la gestione minima del focus
  - modifiche a submit, shortcut tastiera o attachment pipeline
- Moduli confinanti da verificare:
  - auto-focus della chat principale
  - blur esplicito su chiusura/cambio panel
  - submit via `Return` e newline via `Shift+Return`
- Test da aggiungere o aggiornare:
  - regressione su focus deferral del composer
  - smoke manuale su auto-focus iniziale e perdita focus controllata
- Strategia di fix minimo:
  - calcolare il delta tra focus desiderato e focus corrente
  - deferire `makeFirstResponder(...)` su `DispatchQueue.main.async`
  - lasciare invariata la logica di submit e sizing del composer
- Fix previsto:
  - applicare focus/blur asincrono e confinato al solo `ComposerTextView`
  - evitare modifiche di stato durante `updateNSView`
- Verifica post-fix:
  - build del target chat/composer senza warning regressivi
  - scenario manuale: apertura chat con auto-focus, digitazione, blur programmato e ritorno focus senza perdita del cursore
  - scenario manuale: `Return` invia, `Shift+Return` inserisce newline, senza side effect sul focus
- Commit previsto: `fix(chat): defer focus changes in ComposerTextView to prevent state modification during view updates`
