# Changelog — 2026-03-30 — Chat live snapshot refresh fix

## Problema corretto

- Il refresh live usato da task activity e swarm poteva leggere una `messagesConversationSnapshot` stantia.
- Questo riallineava in ritardo tool trace e card subagent anche quando MCP e runtime erano già corretti.
- Il problema si manifestava sia in Codex sia in Claude, senza coinvolgere il layer MCP.

## Fix applicato

- [ChatTaskActivitySnapshotRefreshPolicy.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/Support/ChatTaskActivitySnapshotRefreshPolicy.swift)
  - introdotta una policy pura che sceglie la conversazione corretta per i refresh live
  - preferisce sempre la conversazione del `ChatStore` per il thread selezionato
  - rifiuta conversazioni appartenenti a thread diversi
- [ChatPanelView+PartC_MessageSnapshotScheduling.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageSnapshotScheduling.swift)
  - `refreshTaskActivityDependentSnapshots()` usa la nuova policy
  - quando lo store ha già il thread corretto, forza `refreshMessagesSnapshot()`
  - questo riallinea nello stesso tick messaggi, trace snapshot e live activity snapshot

## Copertura aggiunta

- [ChatTaskActivitySnapshotRefreshPolicyTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTaskActivitySnapshotRefreshPolicyTests.swift)
  - preferenza per la conversazione store del thread selezionato
  - fallback alla snapshot se lo store non è disponibile
  - difesa contro conversazioni di thread errati

## Impatto e rischi

- Impatto atteso: ripristino di interleaving tool e card subagent senza cambiare provider/MCP.
- Rischio residuo: se il `ChatStore` non espone ancora il thread selezionato, il path resta in fallback su snapshot locale; è una scelta intenzionale per non svuotare la UI.
