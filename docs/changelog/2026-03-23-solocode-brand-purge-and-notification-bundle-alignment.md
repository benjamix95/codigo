# 2026-03-23 - Solo Code brand purge and notification bundle alignment

- eliminato il bundle legacy locale dal package workspace e rinominata la risorsa `SoloCode.icns`
- ripulito il perimetro distribuito e runtime dal naming legacy:
  - `Config/Plists/SoloCode-Info.plist`
  - `scripts/release.sh`
  - `scripts/generate_xcode_project.rb`
  - `docs/update/manifest.json`
  - `README.md`
  - path persistenti app support/cache/debug/tool trace/profiling
- riallineati simboli e namespace interni a `SoloCode*` e `com.solocode.*` nel codice applicativo, engine, runtime Monaco e progetto Xcode
- aggiornati i test che dipendevano da path, prompt o identificatori legacy

## Verifica

- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/SystemPromptsTests -only-testing:CoderEngineTests/PipelineJobTests -only-testing:CoderEngineTests/DebugPipelineContractsTests -only-testing:CoderEngineTests/PipelineDebugJobFactoryTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ToolTraceStoreTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/AppDelegateWindowStyleTests -only-testing:SoloCodeAppTests/ExtensionRuntimeTests -only-testing:SoloCodeAppTests/CLIProfileProvisionerTests -only-testing:SoloCodeAppTests/AppUpdateCenterTests`

## Note

- fuori da `docs/**` non risultano più occorrenze legacy nel repo
- il click sulle notifiche torna coerente con l'identità bundle `Solo Code`, eliminando il rischio di riattivare artefatti legacy registrati nel sistema
