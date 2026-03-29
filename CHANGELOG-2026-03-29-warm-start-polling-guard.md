# Changelog — 2026-03-29 — Warm-Start Polling Guard

## Bug Fix Record
- **Categoria**: B — Importante ma non bloccante
- **Bug**: L'indice del codebase riparte sempre da 0% ad ogni avvio dell'app, anche con cache valida
- **Sintomo**: Badge indice mostra 0% per 1-2 secondi all'avvio, poi salta a 62%+ e completa
- **Impatto**: UX degradata — l'utente vede un flash 0% → alto% che suggerisce re-indicizzazione completa
- **Gravità**: Media (non impatta funzionalità, solo percezione)

## Root Cause

Il fix warm-start precedente (commit `18b81b26a` e collegati) impostava correttamente il badge a `.ready` nel `WorkspaceStore.performIndexActiveWorkspace()`. Tuttavia, il **progress polling** (`startProgressPolling`) eseguiva immediatamente una chiamata a `index.status()` sull'attore `CodebaseIndex`, che a quel punto era ancora nello stato iniziale (`.idle`, `_indexingProgress = nil`) — perché il task `indexWorkspace()` non era ancora partito.

La chiamata a `applyIndexStatus(.idle, nil)` sovrascriveva il badge warm-start `.ready` con `.idle`, causando `displayPercent = 0%`.

**Sequenza temporale del bug**:
1. `performIndexActiveWorkspace()` → badge = `.ready` (warm-start) ✓
2. `startProgressPolling()` → primo poll immediato
3. `index.status()` → attore ancora `.idle` (task non ha iniziato)
4. `applyIndexStatus(.idle, nil)` → badge = `.idle`, displayPercent = **0%** ✗
5. (dopo ~50-200ms) `indexWorkspace()` inizia, `_status = .indexing`
6. Prossimo poll → `.indexing` con progress che sale da 62%+

## Fix

**File modificato**: `App/SoloCodeApp/Sources/Services/Project/WorkspaceStore+IndexUI.swift`

Aggiunto un guard in `applyIndexStatus()` che impedisce al polling di sovrascrivere un badge `.ready` (warm-start) con uno stato `.idle` senza progresso:

```swift
if indexBadgeState.status == .ready && info.status == .idle && info.progress == nil {
    return
}
```

Questo guard:
- Protegge solo il caso specifico `.ready` → `.idle` senza progress
- NON blocca transizioni legittime (`.indexing`, `.error`, `.idle` con progress)
- Si disattiva naturalmente appena l'attore entra in stato `.indexing`

## Test di Regressione

**File aggiunto**: `Tests/SoloCodeAppTests/WorkspaceStoreWarmStartPollingTests.swift`

4 test che coprono:
1. `.idle` senza progress NON sovrascrive `.ready` (caso principale)
2. `.indexing` con progress SOVRASCRIVE `.ready` correttamente
3. `.idle` → `.idle` funziona normalmente (nessun warm-start attivo)
4. `.idle` con progress non-nil SOVRASCRIVE `.ready` (edge case)

## Risultati Test

| Suite | Test | Risultato |
|-------|------|-----------|
| WarmStartPollingTests | testApplyIndexStatusDoesNotDowngradeReadyToIdle | ✓ PASS |
| WarmStartPollingTests | testApplyIndexStatusAllowsIndexingToOverrideReady | ✓ PASS |
| WarmStartPollingTests | testApplyIndexStatusAllowsIdleWhenNotWarmStarted | ✓ PASS |
| WarmStartPollingTests | testApplyIndexStatusAllowsIdleWithProgressToOverrideReady | ✓ PASS |
| CodebaseIndexWarmStartTests | (tutti 6 test) | ✓ PASS |

## Scope

- **File modificati**: 1 (`WorkspaceStore+IndexUI.swift`)
- **File aggiunti**: 1 (`WorkspaceStoreWarmStartPollingTests.swift`)
- **Non-scope**: Engine layer, UI layer, sidebar view — non toccati
