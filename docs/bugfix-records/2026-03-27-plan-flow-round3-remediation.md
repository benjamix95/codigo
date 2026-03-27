# Plan / Panel / Task Activity Round 3 Remediation — 2026-03-27

## Bug Fix Record
- Categoria: A/B
- Bug: il terzo audit ha evidenziato incoerenze residue nel flusso `PlanPanel` tra history selection, stato `readyToBuild` e trace live del plan, con rischio di UI pronta al build senza un contenuto realmente buildabile e trace plan non ancora visibile mentre gli eventi sono ancora nel buffer pending.
- Sintomo:
  1. selezionando una voce history o un'opzione senza checklist valida il panel poteva comunque trascinare la phase verso `readyToBuild`
  2. deselezionando la history il panel poteva restare in `readyToBuild`
  3. la trace plan del panel non includeva gli eventi ancora in `pendingActivities`
- Impatto:
  - stato del panel potenzialmente incoerente rispetto al contenuto effettivamente buildabile
  - UX fuorviante nel rebuild da history
  - perdita temporanea di osservabilita' nel live trace plan
- Gravita': medio-alta
- Scope consentito:
  - `PlanPanelView`
  - policy build/history del plan panel
  - query scoped delle task activity
  - test di regressione
- Non-scope:
  - refactor completo di rewind/checkpoint
  - redesign del plan panel
  - nuova architettura di `pendingActivities`
- Strategia di fix:
  1. introdurre un controllo esplicito `hasExecutablePlanBuildChoice`
  2. propagare al parent del panel un booleano `hasBuildChoice` invece di un semplice trigger cieco
  3. riallineare la phase `readyToBuild` solo quando esiste davvero una choice eseguibile
  4. usare `activities + pendingActivities` per la query scoped del live trace plan
- Verifica post-fix:
  - suite mirata `ChatPanelBuildBehaviorTests`
  - suite mirata `TaskActivityStoreScopedActivitiesTests`
- Commit previsto:
  - fix(plan): harden history selection and pending plan trace

## Fix applicati

### P1 — History selection non puo' piu' armare il build senza checklist valida
- introdotto `hasExecutablePlanBuildChoice(...)` in [PlanPanelView+Policy.swift](../../App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+Policy.swift)
- `PlanPanelView` propaga ora `onHistoryEntrySelectedForBuild(Bool)` invece di un callback cieco
- `HistorySection` chiama il parent solo quando la voce o l'opzione selezionata sono davvero buildabili

### P1 — `readyToBuild` torna a `idle` quando la selection non e' buildabile
- il wiring in [ChatPanelView+PartB_SidebarsAndSwarm.swift](../../App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartB_SidebarsAndSwarm.swift) non forza piu' `readyToBuild` in assenza di una build choice valida

### P2 — Trace plan live include anche gli eventi buffered
- aggiunto `activitiesIncludingPending(for:)` nello scope query del `TaskActivityStore`
- `planRelevantRecentActivities(limit:conversationId:)` usa ora `activities + pendingActivities` prima del `suffix(limit)`

## Nota test
- durante la verifica mirata e' emerso un falso negativo nel nuovo test sulle pending activities: il test usava `scheduleAddActivity`, che differisce sul main tick. E' stato corretto a `addActivity`, che popola davvero il buffer pending osservato dalla nuova query scoped.
