# 2026-03-27 — Startup launch: Git refresh alleggerito e indexing iniziale differito

## Modifiche

- `GitService.changedFiles(...)` ora calcola gli stats per-file con due `git diff --numstat` aggregati (`worktree` e `--cached`) invece di lanciare un comando separato per ogni file sporco.
- `GitPanelStore.refresh(...)` carica i dettagli Git estesi (`status`, commit history, remote branches, stash, ahead/behind) solo quando il pannello Git e' aperto; a pannello chiuso aggiorna solo i dati minimi necessari alla UI generale.
- rimossi i trigger duplicati di `gitPanelStore.refresh(...)` dal lifecycle generale di `ChatPanelView`, evitando refresh ridondanti all'avvio e sui cambi conversazione/path gia' coperti da altre view.
- `WorkspaceStore.load()` non avvia piu' immediatamente l'indicizzazione completa: il primo `indexActiveWorkspace()` viene differito di 1 secondo per lasciare respirare il bootstrap UI.
- aggiunto test `GitServiceTests.testChangedFilesIncludesBatchedStatsForStagedUnstagedAndUntrackedFiles`.

## Finding confermati dal sample PID

- prima del fix, il sample dei primi 5 secondi di startup mostrava `GitPanelStore.refresh(...) -> GitService.changedFiles(...) -> GitService.runCommand(...)` come hot path importante, insieme a `WorkspaceStore.indexActiveWorkspace()`.
- dopo il fix, il ricampionamento non mostra piu' `GitService` tra i frame dominanti del launch; resta soprattutto il carico di indicizzazione workspace.

## Verifica

- build app-side completata con `xcodebuild build` sulla scheme `Solo Code-Debug`
- lint dei file toccati: nessun errore
- test mirato `SoloCodeAppTests/GitServiceTests`: non concluso nella sessione per il noto problema di bootstrap del runner app-side macOS
