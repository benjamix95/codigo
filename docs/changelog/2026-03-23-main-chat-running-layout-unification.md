# 2026-03-23 — Main chat running layout unification

## Modifiche
- il main chat non auto-espande piu' la card TODO durante `running`; la checklist resta compatta finche' l'utente non la apre manualmente:
  - [ChatTodoExecutionCardMetrics.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/Blocks/ChatTodoExecutionCardMetrics.swift)
- il `MessageRow` usa la stessa policy inline del reasoning per tutti i provider nel main chat, senza ramo Codex separato:
  - [MessageRow+Content.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/MessageRow/MessageRow+Content.swift)
  - [RustMainChatCLIAccountSnapshots.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatCLIAccountSnapshots.swift)
  - [reasoning_stream.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/reasoning_stream.rs)
- il feed live del main chat riusa ora la stessa regola di visibilita' del trace lineare finale, cosi' gli eventi MCP interni non compaiono piu' solo durante `running`:
  - [ChatPanelView+PartD_MessagesScroll.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartD_MessagesScroll.swift)
  - [ChatPanelSupport+Core.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift)
  - [ToolTraceVisibility.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/ToolTraceVisibility.swift)
- il titolo della trace durante `running` usa lo stesso summary compatto finale, invece del vecchio copy generico `N operazioni in corso...`:
  - [MessageToolTraceView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView.swift)
- estese le regressioni mirate sui punti toccati:
  - [ChatTodoExecutionCardMetricsTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTodoExecutionCardMetricsTests.swift)
  - [ChatReasoningStreamReducerTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatReasoningStreamReducerTests.swift)
  - [ChatTodoVisibilityTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTodoVisibilityTests.swift)
  - [ToolTraceVisibilityTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ToolTraceVisibilityTests.swift)
  - [MessageToolTraceToolIdentityTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/MessageToolTraceToolIdentityTests.swift)
  - [MessageToolTraceMCPCamelCaseTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/MessageToolTraceMCPCamelCaseTests.swift)
- registrato bug record dedicato:
  - [P2-2026-03-23-main-chat-codex-running-layout-was-still-expanded-and-provider-specific.md](/Users/benjaminstoica/SoloCode/docs/bugs/P2-2026-03-23-main-chat-codex-running-layout-was-still-expanded-and-provider-specific.md)

## Risultato
- la card task nel main chat resta piccola e leggibile sia durante l'esecuzione sia a task concluso
- Codex non inietta piu' rumore visuale extra nel feed live del main chat rispetto agli altri provider
- il reasoning e la trace del main chat leggono ora con la stessa grammatica visiva indipendentemente dal provider

## Verifica
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTodoExecutionCardMetricsTests -only-testing:SoloCodeAppTests/ChatReasoningStreamReducerTests -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests -only-testing:SoloCodeAppTests/ToolTraceVisibilityTests -only-testing:SoloCodeAppTests/MessageToolTraceToolIdentityTests -only-testing:SoloCodeAppTests/MessageToolTraceMCPCamelCaseTests CODE_SIGNING_ALLOWED=NO`

## Note
- i pannelli tecnici restano invariati: la riduzione del rumore riguarda solo il main chat timeline
- la differenza visiva piu' evidente arrivava dal feed live, che prima filtrava le activity con una policy diversa da quella usata dal trace finale
