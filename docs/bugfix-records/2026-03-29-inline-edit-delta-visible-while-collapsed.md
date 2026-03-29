# Bugfix Record — 2026-03-29

## Scope
- Nascondere il delta dei file editati quando la row inline della chat è collassata.

## Modifiche
- Introdotta la policy [`ChatTurnInlineFileChangePreviewPolicy.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnInlineFileChangePreviewPolicy.swift) che definisce il comportamento `expandedOnly` per i file change con diff disponibile.
- Aggiornata [`ChatTurnInlineFileChangeRowView.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnInlineFileChangeRowView.swift) per mostrare il delta solo nel ramo espanso.

## Test
- [`ChatTurnInlineFileChangePreviewPolicyTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTurnInlineFileChangePreviewPolicyTests.swift)

## Rischi controllati
- Nessuna modifica al layout della card.
- Nessuna modifica al renderer del diff espanso.
- Nessuna modifica alle card TODO o ad altre superfici.
