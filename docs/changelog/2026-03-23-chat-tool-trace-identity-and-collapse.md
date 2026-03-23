# 2026-03-23 — Chat tool trace identity and collapse

## Modifiche
- la chat assistant usa la card trace inline al posto del vecchio feed lineare di operazioni, così il trace resta nello stesso blocco della risposta e può collassarsi a fine task:
  - [ChatTurnView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnView.swift)
- aggiornato il renderer trace per copy UI in italiano e per un sommario compatto coerente con le famiglie tool mostrate in chat:
  - [MessageToolTraceView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView.swift)
  - [MessageToolTraceView+State.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+State.swift)
  - [MessageToolTraceView+FileChanges.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+FileChanges.swift)
  - [MessageToolTraceView+Helpers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+Helpers.swift)
- corretto il mapping icone/identità tool per non confondere `find_files` con una ricerca generica e per lasciare riconoscibile `semantic_search`:
  - [MessageToolTraceView+EventMetadata.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+EventMetadata.swift)
- estese le regressioni sul trace renderer in un file test già incluso nel target:
  - [MessageToolTraceMCPCamelCaseTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/MessageToolTraceMCPCamelCaseTests.swift)
- aggiunto bug record dedicato:
  - [P2-2026-03-23-chat-tool-trace-card-collapsed-summary-lost-tool-identity.md](/Users/benjaminstoica/SoloCode/docs/bugs/P2-2026-03-23-chat-tool-trace-card-collapsed-summary-lost-tool-identity.md)

## Risultato
- i tool nella chat si leggono come una card trace unica, compatta e collassabile a task concluso
- `semantic_search` non viene più “nascosta” nel riepilogo: le ricerche MCP vengono conteggiate anche quando arrivano come `mcp_tool_call`
- `find_files` usa una semantica visuale da elenco/cartella invece che da semplice ricerca testuale
- il copy della card è coerente con l’interfaccia italiana del progetto

## Verifica
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/MessageToolTraceMCPCamelCaseTests -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests`

## Note
- la causa del “non vedo mai semantic search” non era l’assenza del tool nel runtime: il tool esisteva già, ma la UI chat e il sommario compatto perdevano identità e conteggio di parte delle `mcp_tool_call`
