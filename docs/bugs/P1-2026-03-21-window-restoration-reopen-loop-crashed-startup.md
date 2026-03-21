# P1 - Il ripristino automatico delle finestre poteva mandare l'app in crash all'avvio

## Bug Fix Record
- Priorità: P1
- Categoria: A - Critico
- Bug: l'app poteva crashare nel bootstrap mentre macOS tentava di ripristinare automaticamente la finestra precedente (`restoreWindow...`, `reopenWindowsAsNecessary...`), entrando in un loop di reopen instabile.
- Sintomo:
  - crash immediato all'avvio o al reopen automatico
  - pop-up di reopen non chiudibile o sistema apparentemente bloccato
  - stack trace principale nel layout SwiftUI/AppKit durante il ripristino finestra
- Impatto: impossibilità di avviare l'app in modo affidabile.
- Gravità: alta
- Steps to reproduce:
  1. Chiudere o far crashare l'app lasciando stato finestra persistito.
  2. Riaprire l'app o accettare il reopen proposto dal sistema.
  3. Osservare il crash durante il restore della finestra.
- Risultato attuale: l'app lasciava attivo il ripristino automatico dello stato finestra e poteva riaprire una gerarchia SwiftUI/AppKit incompatibile con lo stato corrente del codice.
- Risultato atteso: l'avvio deve ignorare il restore automatico delle finestre e partire da uno stato pulito.
- Causa probabile:
  - ripristino automatico di una finestra con view tree SwiftUI cambiato
  - assenza di guardrail espliciti contro saved-state restoration
- Scope consentito:
  - `App/SoloCodeApp/Sources/App/AppDelegate.swift`
  - documentazione bug/changelog
- Non-scope:
  - refactor della gerarchia completa `WindowGroup`
  - redesign del launch flow
- Moduli confinanti da verificare:
  - bootstrap finestra principale
  - reopen dopo crash
  - launch pulito da build Debug
- Test da aggiungere o aggiornare:
  - nessun test automatizzato locale affidabile per il restore macOS; verifica build + smoke manuale
- Strategia di fix minimo:
  - disabilitare save/restore automatico dell'application state
  - pulire l'eventuale cartella `savedState` dell'app al launch
- Verifica post-fix:
  - build completa del target app
  - smoke manuale: avvio pulito e reopen senza crash loop
- Commit previsto: `fix(startup): disable window restoration loop`
