# Bug Fix Record — 2026-03-27 — Avvio lento per refresh Git eager e indexing bootstrap

- Categoria: A — Prestazioni / startup
- Bug: l'app macOS builda in tempi ragionevoli ma l'avvio percepito resta lento per lavoro pesante lanciato subito nel bootstrap runtime.
- Sintomo:
  - dopo la compilazione il launch del bundle richiede diversi secondi prima di risultare reattivo;
  - il sample del PID durante i primi 5 secondi mostra lavoro intenso parallelo su indexing workspace e refresh Git;
  - su repo grandi o molto sporchi il rallentamento cresce sensibilmente.
- Impatto: degrado evidente del first paint e della reattivita' iniziale della UI.
- Gravita': alta
- Steps to reproduce:
  1. Buildare `Solo Code-Debug`.
  2. Lanciare `Solo Code.app`.
  3. Campionare il PID nei primi 5 secondi con `sample`.
  4. Osservare i frame di `GitPanelStore.refresh(...)`, `GitService.changedFiles(...)` e `WorkspaceStore.indexActiveWorkspace()`.
- Risultato attuale pre-fix:
  - `GitPanelStore.refresh(...)` partiva anche nel lifecycle generale della chat, non solo dove realmente necessario;
  - `GitService.changedFiles(...)` eseguiva un `git diff --numstat` separato per quasi ogni file sporco;
  - `WorkspaceStore.load()` avviava subito l'indicizzazione completa del workspace durante il bootstrap.
- Risultato atteso:
  - il launch deve evitare lavoro Git esteso quando il pannello Git non e' aperto;
  - le statistiche per-file devono essere raccolte in modo batched, non con N subprocess;
  - l'indicizzazione iniziale deve lasciare respirare il bootstrap UI prima di partire.
- Causa radice confermata:
  - il sample iniziale del PID mostrava `GitPanelStore.refresh(workingDirectory:) -> loadGitPanelRefreshSnapshot(...) -> GitService.changedFiles(...) -> GitService.runCommand(...)`, con attese su `Process.waitUntilExit()` e letture da pipe per decine di invocazioni `git`;
  - lo stesso sample mostrava in parallelo `WorkspaceStore.indexActiveWorkspace() -> CodebaseIndex.indexWorkspace(...)`;
  - dopo il fix, il ricampionamento non mostra piu' frame pesanti `GitService` nel profilo iniziale, mentre resta principalmente il lavoro di indexing.
- Scope del fix:
  - `App/SoloCodeApp/Sources/Git/Services/GitService+Status.swift`
  - `App/SoloCodeApp/Sources/Git/Stores/GitPanelStore+Refresh.swift`
  - `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+LifecycleModifiers.swift`
  - `App/SoloCodeApp/Sources/Services/Project/WorkspaceStore.swift`
  - `Tests/SoloCodeAppTests/GitServiceTests.swift`
- Strategia di fix minimo:
  - sostituire i `git diff --numstat` per-file con due snapshot aggregati (`unstaged` e `--cached`) + fallback solo per path non mappabili;
  - caricare `commitLog`, `remoteBranches`, `stashEntries`, `ahead/behind` e `status` solo quando il pannello Git e' aperto;
  - rimuovere i trigger duplicati di refresh Git nel lifecycle della chat, lasciando i punti di refresh realmente necessari;
  - differire di 1 secondo solo l'indicizzazione iniziale lanciata da `WorkspaceStore.load()`.
- Test / verifica:
  - `xcodebuild build -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS,arch=arm64'` -> OK
  - sample pre-fix su PID startup: presenza chiara di frame `GitService.*` e `WorkspaceStore.indexActiveWorkspace()`
  - sample post-fix su PID startup: frame `GitService.*` non piu' dominanti; resta `WorkspaceStore.indexActiveWorkspace()`
  - `xcodebuild test -only-testing:SoloCodeAppTests/GitServiceTests` non concluso in questa sessione per il noto bootstrap instabile del runner app-side macOS
- Follow-up consigliato:
  - se serve ancora piu' reattivita', rendere `CodebaseIndex` incremental/lazy anche sul primo avvio oppure abbassarne ulteriormente la priorita' iniziale;
  - valutare un sample dedicato dopo comparsa finestra per capire quanto pesa il layout SwiftUI residuo.
