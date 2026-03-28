# 2026-03-29 — Real subagent cards only

## Modifiche
- Rimosso il path UI che inventava `swarm_id` sintetici per eventi `agent` generici solo per forzare la comparsa di card swarm.
  - [ChatPanelView+PartP_Streaming2Continuation+SideEffects.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_Streaming2Continuation+SideEffects.swift)
- Introdotto un gate esplicito: una card subagent viene proiettata nella UI solo se il payload porta metadata swarm reali.
  - [ChatStreamingSwarmProjectionPolicyTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatStreamingSwarmProjectionPolicyTests.swift)
- Registrato bug record dedicato.
  - [P1-2026-03-29-fake-subagent-cards-from-generic-agent-events.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-29-fake-subagent-cards-from-generic-agent-events.md)

## Risultato
- Le card subagent non vengono piu' fabricate da eventi `agent` generici.
- La lane swarm torna ad essere guidata solo da metadata swarm autentici.
- Gli eventi `agent` normali restano visibili come attivita', ma non fingono piu' esecuzioni subagent inesistenti.

## Verifica
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStreamingSwarmProjectionPolicyTests`
