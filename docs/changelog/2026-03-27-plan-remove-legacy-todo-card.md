# 2026-03-27 — Remove legacy todo card from plan chat

## Cosa cambia
- In contesto `Plan` il feed chat non monta più la vecchia todo card legacy del turn assistant.
- Restano solo le superfici corrette del piano: contenuto chat lineare e plan panel.

## Dettagli tecnici
- Aggiunta policy `shouldShowLegacyTodoCardInChat(...)`.
- `shouldShowPlanTodosInChat` usa ora questa policy e ritorna `false` in tutte le fasi/varianti `Plan`.

## Test
- `SoloCodeAppTests/ChatTodoVisibilityTests`
- `SoloCodeAppTests/ComposerTodoOverlayStateTests`
- `SoloCodeAppTests/TodoStoreTests`
- `SoloCodeAppTests/PlanBuildGuardTests`
