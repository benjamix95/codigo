# P1 - Il composer della chat mantiene handler e binding stantii dopo gli update della view

## Bug Fix Record
- Priorità: P1
- Categoria: A - Critico
- Bug: dopo alcuni update SwiftUI del composer, il bridge `NSViewRepresentable` poteva continuare a usare il vecchio `onSubmit` e il vecchio parent binding, lasciando il composer incapace di inviare il messaggio corrente con `Return` o con il pulsante di invio.
- Sintomo:
  - premendo `Enter` nel composer non partiva nessun invio osservabile
  - il bottone `Invia` poteva restare disallineato rispetto al testo effettivamente mostrato nel campo
  - il comportamento risultava più evidente dopo cambi di stato/view update del composer
- Impatto: rottura del flusso core di chat; impossibilità o forte instabilità nell'invio dei messaggi dalla main chat.
- Gravità: alta
- Steps to reproduce:
  1. Aprire la chat principale e portare il focus sul composer.
  2. Innescare un update della view del composer, per esempio cambio stato runtime o refresh dei binding.
  3. Digitare un messaggio e premere `Return` oppure cliccare il bottone `Invia`.
  4. Osservare che il submit può non usare il callback o il binding aggiornato del composer corrente.
- Risultato attuale: il bridge del composer riallineava `onSubmit` solo se `nil` e non aggiornava il `parent` del coordinator su `updateNSView`, lasciando callback/binding stantii dopo i refresh.
- Risultato atteso: ogni update SwiftUI del composer deve riallineare sempre il `parent` del coordinator e la closure `onSubmit`, così `Return` e `Invia` agiscono sullo stato corrente del composer.
- Causa probabile:
  - `ComposerTextView.updateNSView(...)` non riallineava `context.coordinator.parent = self`
  - `textView.onSubmit` veniva aggiornato solo nel caso `nil`, quindi un callback precedente poteva restare agganciato al bridge AppKit
- Scope consentito:
  - `App/SoloCodeApp/Sources/ChatView/Composer/ComposerTextView.swift`
  - `Tests/SoloCodeAppTests/ComposerTextViewFocusTests.swift`
  - documentazione bug/changelog
- Non-scope:
  - modifiche alla pipeline `sendMessage()`
  - redesign UI del composer
  - refactor di altri binding chat non coinvolti nel submit
- Moduli confinanti da verificare:
  - submit via `Return`
  - stato del testo/binding dopo refresh del composer
  - regressione sul focus deferito gia` coperta dai test esistenti
- Test da aggiungere o aggiornare:
  - regressione sul refresh del submit handler verso la closure piu` recente
  - regressione sul refresh del binding testo verso il parent piu` recente
- Strategia di fix minimo:
  - introdurre un helper di sync del bridge
  - riallineare sempre `parent` e `onSubmit` dentro `updateNSView`
  - lasciare invariata la logica di key handling, focus e invio vero e proprio
- Verifica post-fix:
  - `ComposerTextViewFocusTests` con copertura dei nuovi casi di submit/binding stale
  - smoke manuale: digitazione, `Return`, click su `Invia`, refresh UI del composer senza perdita dell'invio corrente
- Commit previsto: `fix(chat): refresh composer submit bindings on view updates`
