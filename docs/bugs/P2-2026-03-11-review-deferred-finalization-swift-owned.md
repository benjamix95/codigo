# P2 — Finalizzazione dei comandi deferred review ancora in Swift

## Sintomo
Il bootstrap app-side decideva ancora in Swift se un comando review deferred dovesse diventare `completed` o `failed`, in base a `phase`, auto-prepare patch e aggiornamento dello stato sorgente.

## Impatto
- logica business duplicata fuori dal core Rust
- fallback incoerente quando la dylib Rust non è caricata nei test Xcode
- rischio di comandi lasciati `processing` o marcati con stato errato

## Fix applicato
- aggiunto `review_command::finalize`
- introdotto l’entrypoint `review_core_command_finalize_deferred`
- spostata in Rust la decisione finale su `completed`/`failed`
- mantenuto un fallback Swift equivalente quando il bridge non è disponibile
- persistito anche lo snapshot `.failed` prima del mark del comando

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests`
