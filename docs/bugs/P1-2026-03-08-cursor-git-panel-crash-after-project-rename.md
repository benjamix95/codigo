# P1 - Cursor Git panel crash dopo rename cartella progetto

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: dopo il rename della cartella progetto da `solocode` a `SoloCode`, il pannello Git di Cursor va in crash e il repository non viene più riconosciuto correttamente.
- Sintomo: aprendo `/Users/benjaminstoica/SoloCode` in Cursor, il pannello Git fallisce; da terminale `git status` termina con errori su worktree/submodule non validi.
- Impatto: workflow Git locale rotto, impossibilità di usare in modo affidabile status/diff/pannello SCM in Cursor.
- Gravità: alta lato developer workflow
- Steps to reproduce:
  1. Rinominare la root locale del progetto da `solocode` a `SoloCode`.
  2. Aprire `/Users/benjaminstoica/SoloCode` in Cursor.
  3. Aprire il pannello Git oppure eseguire `git status` da terminale nella root.
- Risultato attuale: Git tenta di risolvere metadata locali riferiti al vecchio path `solocode` e una entry tracked sotto `.claude/worktrees/brave-proskuriakova`; il pannello Git non riesce a calcolare lo stato del repository.
- Risultato atteso: il repository deve risultare leggibile da Cursor e da CLI dopo il rename della cartella, senza attraversare worktree locali/tooling non versionati.
- Causa probabile: combinazione di due problemi locali emersi dopo il rename. Primo: un admin entry Git stale in `.git/worktrees/brave-proskuriakova` puntava ancora a `/Users/benjaminstoica/SoloCode/...`. Secondo: il path `.claude/worktrees/brave-proskuriakova` era stato registrato in index come gitlink (`160000`) pur non avendo alcuna definizione valida in `.gitmodules`, quindi `git status` entrava in logica submodule su un worktree locale non versionabile.
- Scope consentito: `.gitignore`, index Git del repository, documentazione bug/changelog.
- Non-scope: codice applicativo, refactor del progetto, pulizia generale dei metadata agent, rename di remote/branch/repository GitHub.
- Moduli confinanti da verificare: stato Git root, scanning worktree locali `.claude`, pannello SCM di Cursor.
- Test da aggiungere o aggiornare: scenario manuale ripetibile con `git status`, `git worktree list --porcelain` e verifica apertura pannello Git in Cursor.
- Strategia di fix minimo: rimuovere il record worktree stale dal metadata locale Git, smettere di tracciare il gitlink spurio sotto `.claude/worktrees/` e ignorare l'intera directory per evitare regressioni.
- Verifica post-fix:
  1. `git worktree prune -v`
  2. `git update-index --force-remove -- .claude/worktrees/brave-proskuriakova`
  3. `git status --short --branch`
  4. `git ls-files -s | rg '\\.claude/worktrees|160000'`
  5. Verifica manuale del pannello Git in Cursor sulla cartella `/Users/benjaminstoica/SoloCode`
- Commit previsto: `fix(repo): ignore local claude worktrees`
