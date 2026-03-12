# 2026-03-12 - Review panel live dismiss via Rust mutator

## Modifiche
- `CodeReviewSessionState+RustSnapshot.swift` espone l'applicazione dello snapshot canonico anche al path app-side.
- introdotto `mutateLiveSessionUsingRust(...)` in `CodeReviewPanelStore+SnapshotMutation.swift`.
- `CodeReviewPanelStore+Launch.swift` ora usa il mutator Rust anche per la dismiss di finding su sessioni live.
- aggiunto test dedicato `CodeReviewPanelLiveMutationRustTests.swift`.
- aggiornato `Solo Code.xcodeproj/project.pbxproj` per includere il nuovo file di test.

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelLiveMutationRustTests`

## Note
- la suite Rust e' verde.
- il build app-side passa fino al launch della suite; il run resta bloccato dall'instabilita' ambientale LaunchServices/Xcode gia' nota.

## Esito
- live dismiss e fallback dismiss condividono ora lo stesso mutator Rust
- il boundary panel/live elimina un altro path semantico duplicato in Swift
