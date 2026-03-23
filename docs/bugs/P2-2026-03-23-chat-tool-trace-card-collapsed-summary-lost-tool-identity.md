# Bug Fix Record
- Categoria: B
- Bug: la chat principale mostrava il trace tool con un feed lineare/generico oppure con un sommario che non contava correttamente molte `mcp_tool_call`; il risultato era una card poco leggibile, senza identità chiara per `semantic_search`, `find_files`, `read` e altre modalità.
- Sintomo: nella chat i passi apparivano come operazioni generiche; `semantic_search` sembrava non essere mai usata, `find_files` finiva visivamente tra le ricerche e il riepilogo non rifletteva bene letture/ricerche/elenchi.
- Impatto: feedback operativo degradato durante i turni agent; minore fiducia nella telemetria della chat e scarsa leggibilità del trace a task concluso.
- Gravità: media
- Steps to reproduce:
  1. Avviare un turno chat che emetta `mcp_tool_call` per `read`, `codebase_search`, `semantic_search` e `find_files`.
  2. Osservare la timeline tool dentro la risposta assistant.
  3. Verificare che il riepilogo compatto non distingua bene letture/ricerche/elenchi e che `semantic_search` non emerga come tool riconoscibile.
- Risultato attuale: il renderer chat appiattisce o sottoconta parte delle operazioni MCP; la card non comunica in modo coerente le famiglie tool e `find_files` usa una semantica di ricerca invece che di elenco/cartella.
- Risultato atteso: la chat deve usare la card trace collassabile, mostrare icone coerenti per famiglia tool, contare correttamente `read`/`read_range`, `codebase_search`/`semantic_search` e `find_files`, e mantenere il collapse automatico a fine task.
- Causa probabile: il sommario `MessageToolTraceView.DerivedState.computeCollapsedSummary(...)` guardava soprattutto `event.type` e perdeva molte operazioni arrivate come `mcp_tool_call`; inoltre il resolver icone trattava `find_files` come ricerca generica.
- Scope consentito:
  - `App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnView.swift`
  - `App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/**`
  - `Tests/SoloCodeAppTests/MessageToolTraceMCPCamelCaseTests.swift`
  - `docs/bugs/**`
  - `docs/changelog/**`
- Non-scope:
  - runtime tool execution
  - prompt/policy dei provider
  - catalogo MCP o implementazione di `semantic_search`
  - pannelli Debug/Plan non-chat
- Moduli confinanti da verificare:
  - `ToolTraceVisibility`
  - `ChatTurnView`
  - `MessageToolTraceView`
  - mapping icone/metadata trace
- Test da aggiungere o aggiornare:
  - riepilogo trace che conteggi `read`, `semantic_search`, `codebase_search`, `find_files`
  - regressione icona `find_files` -> `folder`
  - copy UI running header italiano
- Strategia di fix minimo:
  - usare nella chat la card trace già predisposta
  - correggere solo sommario/icone/copy del trace renderer, senza toccare il runtime dei tool
  - aggiungere regressioni nello stesso file test già agganciato al target
- Verifica post-fix:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/MessageToolTraceMCPCamelCaseTests -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests`
- Commit previsto: `fix(chat): surface collapsible tool trace identity`
