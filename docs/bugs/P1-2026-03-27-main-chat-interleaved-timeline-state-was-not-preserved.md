# P1 — 2026-03-27 — main chat interleaved timeline state was not preserved

## Sintesi

La main chat perdeva lo stato della timeline interleavata `text/tool/text` durante i round-trip Swift/Rust della pipeline chat. Il risultato osservabile era una resa a blocchi: testo assistant finale separato dai tool trace, con fallback che spostava il testo in fondo alla risposta.

## Impatto

- il flusso reale del turno veniva rappresentato in modo fuorviante
- i `toolMarker` non sopravvivevano lungo tutta la pipeline
- il renderer Swift cadeva spesso nel caso `single monolithic text`
- la risposta assistant poteva apparire tutta sotto mentre gli strumenti restavano sopra

## Causa probabile

- `ChatTurnState` lato Swift non tracciava `textSegments`, `timelineSegments` e `timelineNextSequence`
- `MainChatBridgeState` non preservava quei campi quando il runtime passava attraverso il bridge Rust
- il restore da store ricostruiva solo testo aggregato e artifact, senza ricostruire la timeline interleavata

## Priorità

- `P1`

## Aree coinvolte

- `App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Core`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Adapters`
- `App/SoloCodeApp/Sources/Runtime`
- `Tests/SoloCodeAppTests`

## Fix applicato

- aggiunti i campi timeline mancanti a `ChatTurnState` Swift
- allineato il reducer Swift al reducer Rust per segmentare `text`, `reasoning` e `toolUse`
- preservati i segmenti nel bridge `MainChatBridgeState`
- ricostruita la timeline interleavata nel restore da store
- aggiunti test di regressione per blocchi `primaryText/toolMarker/primaryText` e round-trip del bridge

## Verifica

- `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::reducer -- --nocapture`
- `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui_state_sync -- --nocapture`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPipelineTimelineStateTests -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/ChatTimelineInterleavingTests`
