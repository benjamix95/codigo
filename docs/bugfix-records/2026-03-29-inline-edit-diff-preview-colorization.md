# Bugfix Record — 2026-03-29

## Scope
- Colorare semanticamente il delta dei file editati nelle preview compatte ed espanse della chat.

## Modifiche
- Aggiunto parsing per riga del diff in [`ToolTraceFileChange+DiffLines.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Models/ToolTraceFileChange+DiffLines.swift) con classificazione `addition`, `removal`, `hunk`, `metadata`, `context`.
- Aggiunta view riusabile [`ToolTraceFileChangeDiffLinesView.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Views/FileChanges/ToolTraceFileChangeDiffLinesView.swift) per renderizzare il diff colorato senza cambiare il layout della card.
- Aggiornata [`ToolTraceFileChangeExpandedPreviewCardView.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Views/FileChanges/ToolTraceFileChangeExpandedPreviewCardView.swift) per usare il renderer a righe invece del testo monolitico.
- Aggiornata [`ToolTraceFileChangeCompactPreviewView.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Views/FileChanges/ToolTraceFileChangeCompactPreviewView.swift) così anche la preview compatta eredita la stessa colorazione semantica.

## Test
- [`ToolTraceFileChangeDiffLinesTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ToolTraceFileChangeDiffLinesTests.swift)

## Rischi controllati
- Nessuna modifica alla struttura visiva della card.
- Nessuna modifica alla persistenza o al parsing del payload originale.
- Nessuna modifica al comportamento di expand/collapse.
