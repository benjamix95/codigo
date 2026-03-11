# P1 — Run/attach macOS falliva perché Xcode non trovava il processo `Solo Code`

## Bug Fix Record
- Categoria: A
- Bug: il launch da Xcode poteva fallire con `IDEDebugSessionErrorDomain Code=3` e messaggio `could not find a process named Solo Code`.
- Sintomo: l’IDE provava ad agganciare il debugger a `pid 0` o a un processo non trovato, anche se il prodotto buildava correttamente.
- Impatto: impossibilità di lanciare l’app in debug da Xcode in modo affidabile.
- Gravita': alta, perché blocca il workflow di esecuzione/debug locale.
- Steps to reproduce:
  1. Buildare il target `Solo Code`.
  2. Lanciare la scheme `Solo Code-Debug`.
  3. Osservare l’errore di attach e assenza del processo agganciabile.
- Risultato attuale: il bundle e la scheme devono essere coerenti; il build non deve introdurre warning/config che destabilizzano il launch path.
- Risultato atteso: `Solo Code.app` builda e si lancia come bundle macOS senza errori di attach dipendenti dal progetto.
- Causa probabile: combinazione di stato Xcode/DerivedData e configurazione build con explicit modules che generava rumore e instabilità nel launch path; il prodotto bundle resta però coerente e lanciabile.
- Scope consentito:
  - `Config/xcconfigs/Common.xcconfig`
  - file Swift con warning locali collegati alla build
- Non-scope:
  - refactor scheme/project file auto-riscritti da Xcode
  - modifiche ai package remoti SwiftPM
- Moduli confinanti da verificare:
  - build `Solo Code-Debug`
  - launch bundle macOS
  - test review/history già toccati
- Test da aggiungere o aggiornare:
  - nessun test unitario dedicato; verifica tramite build e launch bundle
- Strategia di fix minimo:
  - disabilitare `SWIFT_ENABLE_EXPLICIT_MODULES` via xcconfig comune
  - pulire i warning Swift locali segnalati dal compilatore
- Verifica post-fix:
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS,arch=arm64'`
  - lancio bundle app e verifica presenza processo
- Commit previsto: `build(review): silence explicit modules and local swift warnings`
