# P2 - I file editati inline spariscono dentro i gruppi tool collassati

## Bug Fix Record
- Categoria: B - Importante
- Bug: gli eventi di modifica file nella timeline chat inline venivano collassati insieme ai tool group e sparivano quando l'utente chiudeva la sezione.
- Sintomo: il chevron nascondeva anche le righe dei file editati, impedendo una lettura rapida dei cambi applicati.
- Impatto: peggiora l'ispezione del turno completato e rende piu' costoso capire cosa e' stato toccato.
- Gravita': P2
- Scope consentito: `App/SoloCodeApp/Sources/ChatView/Timeline/*`, test inline trace nuovi e documentazione bug/changelog.
- Non-scope: pannello trace dettagliato, store trace, policy di grouping fuori dalla timeline lineare.
- Expected result: i gruppi `exploration` e `terminal` restano collassabili; gli edit file devono restare righe standalone visibili.
- Rischi laterali: regressioni nell'ordine cronologico dei segmenti se il grouping inline cambia il perimetro sbagliato.

## Findings prioritizzati

### 1) P2 - Il grouping inline trattava gli edit come sezione collassabile
- File:
  - `App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnTimelineInterleaver.swift`
  - `App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnInlineToolGroupingPolicy.swift`
- Causa probabile:
  - `collapsedConsecutiveToolEvents()` raggruppava ogni categoria restituita da `toolGroupCategory`, inclusa `.edit`.
- Fix applicato:
  - introdotta una policy dedicata che limita il collapse ai gruppi `exploration` e `terminal`.

### 2) P3 - La riga standalone del file change non usava il titolo presentazionale
- File:
  - `App/SoloCodeApp/Sources/ChatView/Timeline/InlineToolTraceViews.swift`
- Sintomo:
  - alcuni edit standalone potevano mostrare label grezze tipo `apply_patch` invece di una descrizione leggibile del file toccato.
- Fix applicato:
  - la view usa `ToolTraceFileChange.displayTitle` per il titolo primario e mantiene i contatori `+/-` nel dettaglio compatto.
