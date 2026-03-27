# 2026-03-27 — Plan composer/chat todo scope fix

## Cosa cambia
- Il composer overlay in contesto `Plan` non mostra più runtime todo legacy del thread.
- La todo card del turn assistant durante plan/build usa ora solo i canonical todos del piano corrente.
- I canonical todos del plan non sono stati modificati; è cambiato solo il filtro delle superfici UI che li presentano.

## Dettagli tecnici
- Aggiunta query `displayPlanScopedTodos(...)` in `TodoStore+Queries`.
- `displayTodosForComposer(..., includeOperationalRuntimeTodos: true)` ora usa il dataset plan-scoped e aggiunge solo placeholder operativi scoped alla stessa `conversationId`.
- `ChatPanelView+PartD_MessageCell` usa lo stesso dataset plan-scoped per la todo card del turn assistant, evitando la contaminazione da runtime todo storici.

## Test
- Estesi `TodoStoreTests` con regressioni su:
  - esclusione dei legacy runtime todos nel composer plan overlay
  - esclusione dei legacy runtime todos nella lista plan-scoped usata dalla chat
