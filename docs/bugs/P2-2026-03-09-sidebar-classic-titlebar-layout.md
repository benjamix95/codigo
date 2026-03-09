# P2 - Sidebar non classica: blocco top interno separa visivamente i semafori dal pannello

## Bug Fix Record
- Categoria: Categoria B — importante ma non bloccante
- Bug: la sidebar chat/workspace veniva resa con un blocco vuoto nella parte alta invece di una colonna continua in stile sidebar macOS classica.
- Sintomo: i semafori della finestra risultavano visivamente "fuori" dal pannello della sidebar e il contenuto iniziava sotto un box top separato.
- Impatto: degrado UX e coerenza visiva; la sidebar sembra una card interna invece di una sidebar nativa con toggle custom.
- Gravità: P2
- Steps to reproduce:
  1. Avviare l'app macOS.
  2. Aprire una finestra in modalità con sidebar visibile.
  3. Osservare l'area top sinistra con titlebar trasparente e controlli finestra.
- Risultato attuale: la colonna sidebar veniva resa come pannello inset separato e il contenuto partiva troppo in basso, lasciando i semafori visivamente fuori dal blocco principale.
- Risultato atteso: la sidebar deve restare una colonna continua fino al bordo superiore; il contenuto deve partire sotto i semafori senza introdurre un box top separato.
- Causa probabile: poi confermata. La `NavigationSplitView` della modalità chat era forzata su `.prominentDetail`, facendo apparire la sidebar come un pannello interno invece di una colonna classica; in più l'inset top di `SidebarView` era più alto del necessario.
- Scope consentito:
  - [ContentView+Layout+Composition.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Content/Sections/ContentView+Layout+Composition.swift)
  - [SidebarView+Sections+Core.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Sidebar/Sections/SidebarView+Sections+Core.swift)
- Non-scope: refactor del layout globale, modifiche a `WindowSidebarToggleController`, redesign del toggle custom, restyling del workbench IDE.
- Moduli confinanti da verificare: layout della sidebar standard, toggle apertura/chiusura colonna, sezioni `quickActions`, `contextSection`, `threadsSection`.
- Test da aggiungere o aggiornare: nessun harness UI/snapshot locale dedicato a questa gerarchia; validazione tramite build workspace e scenario manuale ripetibile.
- Strategia di fix minimo: riportare la split view a uno stile sidebar classico e ridurre solo l'inset superiore della `SidebarView`, senza toccare il toggle custom o il chrome della finestra.
- Verifica post-fix:
  1. Build del workspace macOS.
  2. Verifica manuale della sidebar con semafori sovrapposti alla stessa superficie visiva della colonna.
  3. Verifica del toggle custom di apertura/chiusura sidebar.
- Commit previsto: `fix(sidebar): restore classic titlebar-aligned layout`
