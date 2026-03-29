# Bug Fix Record — 2026-03-29 — Chiarezza panel/strip sub-agents e spinner

- **Categoria:** B — Importante ma non bloccante
- **Bug:** la strip inline e il pannello sub-agents mescolavano attivi e completati nella stessa superficie, e l’indicatore di esecuzione dei sub-agent non era abbastanza leggibile.
- **Sintomo:** i completati restano nella lista “live”, non è immediato capire cosa è ancora attivo, e il cerchio tratteggiato comunica poco il fatto che il sub-agent sia in esecuzione.
- **Impatto:** UX meno chiara in strip e panel, stato dei sub-agent più difficile da leggere a colpo d’occhio.
- **Gravità:** Media
- **Steps to reproduce:**
  1. Lanciare più sub-agent.
  2. Lasciarne alcuni `running` e altri `completed/failed`.
  3. Guardare la strip inline e il panel sub-agents.
- **Risultato attuale:** i completati possono restare assieme ai live; l’icona non distingue bene la sezione sub-agents; lo spinner è troppo lento e troppo denso.
- **Risultato atteso:** strip e panel mostrano prima gli attivi e poi i finiti, con stato esplicito; la sezione sub-agents usa un’icona più adatta; lo spinner dei sub-agent è più veloce e con meno tacche.
- **Causa probabile:** mancava una partizione condivisa `active/finished` riusata da panel e strip, e lo spinner usava l’icona di sistema `circle.dotted` senza personalizzazione.
- **Scope consentito:** `SwarmProgressView*`, `SwarmPanelView*`, `SpinningDottedCircle`, test helper di partizione.
- **Non-scope:** reducer swarm, protocollo provider, timeline interleaver già corretti nei commit precedenti.
- **Moduli confinanti da verificare:**
  - strip inline `SwarmProgressView+InlineLiveCards`
  - panel `SwarmPanelView+Overview`, `+TopBar`, `+BottomBar`
  - indicatore `SpinningDottedCircle`
- **Test da aggiungere o aggiornare:**
  - partizione active/finished delle card per presentazione
  - regressione su timeline/presentation già esistenti per assicurare che il refactor non le rompa
- **Strategia di fix minimo:**
  - introdurre una utility pura di partizione `partitionSubagentCardsForPresentation`
  - usare quella utility sia nella strip inline sia nel panel
  - aggiornare icone e spinner senza toccare il runtime
- **Verifica post-fix:**
  - `xcodebuild test -quiet -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTimelineInterleavingSubagentTests -only-testing:SoloCodeAppTests/ChatTurnCompletedSubagentsGroupPresentationTests -only-testing:SoloCodeAppTests/SwarmCardPresentationPartitionTests`
- **Commit previsto:** `fix(ui): separate active and finished subagents in panel`
