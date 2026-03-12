# [P2] Il runner `xcodebuild test` può fallire a caricare `CoderEngineTests.xctest` per policy di firma

## Contesto
- emerso durante rilanci selettivi della suite `xcodebuild test`
- failure osservato dopo rebuild completi del target app/test

## Sintomo
- `xctest` fallisce con:
  - `code signature ... not valid for use in process: library load denied by system policy`

## Impatto
- alcune validazioni `xcodebuild test` diventano non affidabili nello stesso worktree/sessione
- il problema non punta direttamente alla logica MCP migrata, ma inquina la verifica end-to-end

## Osservazione
- il problema è distinto dal crash `SIGPIPE`
- i test MCP mirati erano passati prima che il runner entrasse in questo stato

## Stato
- aperto
- da investigare come problema separato di signing / DerivedData / policy locale del runner
