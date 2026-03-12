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
- il problema non è stato eliminato dal fix su `bootstrap_test_bundles.sh`
- anche dopo build `build-for-testing`, bootstrap esplicito e rifirma manuale del bundle, `xctest` continua a rifiutare `CoderEngineTests.xctest`
- il runner `xcodebuild test` costruisce e tenta di caricare un bundle che il sistema considera ancora `not valid for use in process`

## Evidenza aggiornata
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'` passa
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests` continua a fallire al load del bundle
- anche `xcodebuild test-without-building` sul file `.xctestrun` fallisce con lo stesso `library load denied by system policy`
- durante il build dei target test, Xcode continua a rifirmare `CoderEngineTests.xctest` e i framework annidati con:
  - `codesign --sign -`
  - `builtin-swiftStdLibTool --sign -`
- quindi il problema residuo non è più il bootstrap script ma la catena di signing usata dal runner/toolchain per i test bundle su questa macchina

## Stato
- aperto
- da investigare come problema separato di signing / DerivedData / policy locale del runner
