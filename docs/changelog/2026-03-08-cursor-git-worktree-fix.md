# 2026-03-08 - Cursor Git worktree fix dopo rename progetto

- Documentato il bug di integrazione Git/Cursor in [P1-2026-03-08-cursor-git-panel-crash-after-project-rename.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-08-cursor-git-panel-crash-after-project-rename.md).
- Aggiunta in [/Users/benjaminstoica/SoloCode/.gitignore](/Users/benjaminstoica/SoloCode/.gitignore) la regola `.claude/worktrees/` per escludere worktree locali di tooling dal contenuto versionato.
- Ripulito il metadata locale Git con `git worktree prune -v` per rimuovere l'entry stale `brave-proskuriakova` ancora puntata al vecchio path `/Users/benjaminstoica/codigo/...`.
- Rimossa dall'index la entry gitlink spuria `.claude/worktrees/brave-proskuriakova` con `git update-index --force-remove`, così Git non tratta più un worktree locale come submodule incompleto.
