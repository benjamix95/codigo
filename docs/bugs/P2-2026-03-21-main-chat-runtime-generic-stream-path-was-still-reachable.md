# Bug Fix Record
- Categoria: B
- Bug: il runtime della main chat poteva ancora transitare nel generic stream runner Swift del `ConversationFlowCoordinator`.
- Sintomo: il path Rust-only della main chat non falliva in modo chiuso quando arrivava su un provider generico; manteneva codice Swift legacy per timeout, iterazione stream e riduzione eventi.
- Impatto: ownership Rust incompleta nel dominio `Runtime`, maggiore rischio di regressioni tra coordinator legacy e transport Rust.
- Gravità: media
- Steps to reproduce:
  1. Avviare `ConversationFlowCoordinator.runStream(...)` con un provider non `MainChatRustTransportProvider`.
  2. Forzare un percorso main-chat runtime con Rust atteso come source of truth.
  3. Osservare che il coordinator entra ancora nel loop stream Swift legacy.
- Risultato attuale: il coordinator esegue logica generic stream legacy invece di rifiutare il path non-Rust.
- Risultato atteso: il path runtime della main chat deve essere fail-closed fuori dal boundary Rust-only.
- Causa probabile: il coordinator conservava un fallback storico usato prima del cutover completo del transport runtime.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift`
  - `App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift`
  - `Tests/SoloCodeAppTests/ConversationFlowCoordinatorTests.swift`
  - `App/SoloCodeApp/Sources/Runtime/DebugPipeline/*`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - bridge Rust/FFI già verdi
  - account/provider resolution
  - persistenza/rewind
- Moduli confinanti da verificare:
  - `ConversationFlowCoordinator`
  - `WorkspaceStore`
  - `DebugPipeline`
  - `GitService` per il delta strutturale già aperto nel worktree
- Test da aggiungere o aggiornare:
  - aggiornare `ConversationFlowCoordinatorTests` per usare il transport Rust bridge nei casi coperti
  - smoke test `WorktreeMergeAIServiceTests`
  - smoke test `GitServiceTests`
- Strategia di fix minimo:
  - rimuovere il loop generic stream Swift dal path runtime della main chat
  - mantenere il comportamento fail-closed
  - spezzare il riassetto `DebugPipeline` in file sotto soglia
- Verifica post-fix:
  - `xcodebuild test` sui test runtime/git toccati
  - `validate_rust_cutover_boundary.sh` sul diff della tranche
- Commit previsto: `refactor(runtime): retire generic stream fallback from main chat`
