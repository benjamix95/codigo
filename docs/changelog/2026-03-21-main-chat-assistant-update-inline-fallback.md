## 2026-03-21

## Modifiche
- aggiunto un fallback pipeline-side in [PipelineIntegrationService+EventSupport.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift) che converte i raw `assistant_update` in `textReplace` sullo stream del task corrente mentre il turno e' ancora streaming
- il fallback usa lo `stream_id` del task pipeline attivo, cosi' il testo primario finisce nello stesso `textByStreamId` del path normale e non crea stream duplicati
- bloccati gli overwrite tardivi: dopo `jobCompleted`/`jobFailed` i raw `assistant_update` non possono piu' rimpiazzare il body finale della chat

## Test
- aggiunti test dedicati in [PipelineIntegrationAssistantUpdateTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/PipelineIntegrationAssistantUpdateTests.swift) per:
  - proiezione del raw `assistant_update` in `primaryTextSnapshot`
  - protezione contro overwrite tardivo dopo completion

## Validazione
- da eseguire:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationAssistantUpdateTests`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/ChatPipelineReducerTests`

## Rischio controllato
- nessuna modifica al parser Codex CLI o al reducer Rust
- nessuna modifica al rendering della timeline
- fallback confinato al path `agent` della pipeline, con guardia esplicita sui turni gia' completati
