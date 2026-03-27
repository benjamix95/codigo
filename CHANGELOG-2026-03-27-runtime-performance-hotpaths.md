# Changelog

Data: 2026-03-27
Tema: runtime/performance hot paths

## Modifiche

- spezzato `ConversationFlowCoordinator` in moduli distinti e portati sotto la soglia di righe
- batchati i raw event consecutivi nello stream chat e aggiunta una policy per evitare flush testo troppo frequenti
- ridotto l’overhead del `DebugLogServer` con encoder condiviso e file handle riusabili
- introdotta backoff comune per polling login e backoff progressivo nel buffer LLDB
- aggiunto debounce alla persistenza del `CLIAccountUsageLedgerStore`
- introdotto fast-path `git ls-files` in `WorkspaceScanner`

## Test

- `xcodebuild test -quiet -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/SoloCodeValidateScriptTests -only-testing:CoderEngineTests/DebugLogServerPersistenceTests -only-testing:CoderEngineTests/WorkspaceScannerTests -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/ConversationFlowStreamingPolicyTests -only-testing:SoloCodeAppTests/LoginPollingBackoffTests -only-testing:SoloCodeAppTests/CodexLoginServiceTests -only-testing:SoloCodeAppTests/CLIAccountUsageLedgerStoreTests -only-testing:SoloCodeAppTests/DebugService/LLDBPersistentSessionPollingTests`
