# 2026-03-27 — Hide composer todo overlay during plan

## Cosa cambia
- In contesto `Plan` il composer non mostra più il `todo overlay` sopra la chat.
- I placeholder operativi non contano più come contenuto visibile dell’overlay e non entrano più nella signature di auto-expand.

## Dettagli tecnici
- Aggiunta policy `shouldShowComposerTodoOverlay(...)` per sopprimere il mount del `topOverlay` del composer in tutte le fasi `Plan`.
- `hasVisibleComposerTodoOverlay(...)` e `composerTodoAutoExpandSignature(...)` ora ignorano i `isOperationalPlaceholder`.

## Test
- `SoloCodeAppTests/ComposerTodoOverlayStateTests`
- `SoloCodeAppTests/TodoStoreTests`
- `SoloCodeAppTests/PlanBuildGuardTests`
