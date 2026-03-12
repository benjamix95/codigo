# [P1] Il target `CoderEngine` non includeva i nuovi file del bridge MCP lifecycle Rust

## Contesto
- emerso durante la tranche di migrazione del lifecycle MCP fuori da Swift
- sono stati aggiunti nuovi file Swift sotto `Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle`

## Sintomo
- `xcodebuild` falliva in compilazione con:
  - `cannot find type 'MCPLifecycleRustBackend' in scope`
- la causa non era il codice del bridge, ma il fatto che i file non erano ancora agganciati al target `CoderEngine` nel `.xcodeproj`

## Impatto
- build rotta del framework `CoderEngine`
- impossibile validare il nuovo path Swift→Rust fino al fix del wiring del progetto

## Fix applicato
- aggiunti al target `CoderEngine` i file:
  - `MCPLifecycleRustModels.swift`
  - `MCPLifecycleRustBinaryLocator.swift`
  - `MCPLifecycleRustBackend.swift`
  - `MCPSessionManager+RustLifecycleBridge.swift`

## Validazione
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`

## Stato
- risolto
