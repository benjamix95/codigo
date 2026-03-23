# P1 — La shape persistita review/bughunter restava ancora costruita manualmente in Swift

## Bug Fix Record
- Categoria: A
- Bug: snapshot review, snapshot bughunter e code review command queues venivano ancora serializzati/deserializzati direttamente da Swift nei path file e Postgres.
- Sintomo: il core Rust governava pipeline, MCP e lifecycle, ma la shape persistita cross-process restava in un secondo punto di verità lato Swift.
- Impatto: rischio di drift tra stato canonico Rust e payload persistiti, soprattutto su snapshot review/bughunter e queue comandi.
- Gravita': alta, perché tocca persistence e recovery cross-process.
- Steps to reproduce:
  1. Eseguire write/read di snapshot review o bughunter via `MCPSharedState` o Postgres.
  2. Osservare che `JSONEncoder/Decoder` Swift costruivano ancora la shape persistita.
  3. Confrontare con il core Rust già usato per pipeline/MCP.
- Risultato attuale: encode/decode review/bughunter/commands devono passare da un adapter Rust canonico, con Swift limitato a lock e I/O effettivo.
- Risultato atteso: la serializzazione cross-process del review stack non dipende più da shape Swift costruite manualmente.
- Causa probabile: le tranche precedenti avevano migrato orchestration e MCP ma non il boundary persistence.
- Scope consentito:
  - `Native/RustCore/src/review_persistence/*`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/*`
  - `Engine/CoderEngine/Sources/PersistenceCore/*`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - UI SwiftUI
  - provider/gitreview runtime
  - patch executor concrete side effects
- Moduli confinanti da verificare:
  - `MCPSharedCodeReviewSnapshotStoreTests`
  - `MCPSharedCodeReviewCommandsTests`
  - `MCPSharedBugHunterCommandsTests`
  - `SoloCodeAppCodeReviewCommandLoopTests`
- Test da aggiungere o aggiornare:
  - unit test Rust su codec persistence
  - smoke tests file/store review snapshot
  - smoke tests app-side command loop review
- Strategia di fix minimo:
  - introdurre `review_persistence` nel core Rust
  - aggiungere `ReviewPersistenceRustAdapter` in Swift
  - instradare file persistence e il path Postgres review/bughunter attraverso l’adapter
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSharedCodeReviewSnapshotStoreTests -only-testing:CoderEngineTests/MCPSharedCodeReviewCommandsTests -only-testing:CoderEngineTests/MCPSharedBugHunterCommandsTests -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests`
- Commit previsto: `perf(review): move persistence payload shaping into rust core`
