# Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: in contesto `Plan` la vecchia todo card legacy del feed chat veniva ancora montata sul turn assistant.
- Sintomo:
  - espandendo la card ricompariva un blocco todo sopra il piano;
  - la card era persistente nella timeline e non dipendeva più dal composer overlay;
  - l’utente percepiva una “vecchia card” che non doveva esistere nel flow plan.
- Impatto: duplicazione delle superfici plan e persistenza di un componente legacy nel feed chat.
- Gravità: P1
- Steps to reproduce:
  1. Entrare in `Plan`.
  2. Generare un piano e/o premere `Build`.
  3. Espandere la todo card legacy visibile nel turn assistant.
- Risultato attuale: `ChatTurnView` riceve ancora `shouldShowTodo = true` in contesto plan, quindi la vecchia card viene renderizzata.
- Risultato atteso: in contesto `Plan` la card todo legacy non deve proprio essere montata nel feed chat.
- Causa probabile:
  - `shouldShowPlanTodosInChat` dipendeva solo da segnali swarm/pipeline, senza escludere esplicitamente il contesto plan.
- Scope consentito:
  - `ChatPanelView+DisplayFlags.swift`
  - test `ChatTodoVisibilityTests`
- Non-scope:
  - modifiche ai canonical todos del piano
  - modifiche al plan panel
- Moduli confinanti da verificare:
  - visibility policy della todo card legacy
  - comportamento agent non-plan
- Test da aggiungere o aggiornare:
  - hidden during plan surface
  - visible during regular agent execution
- Strategia di fix minimo:
  - introdurre una policy pura che disabilita la legacy todo card quando il thread è in `Plan`;
  - usare quella policy nel flag `shouldShowPlanTodosInChat`.
- Verifica post-fix:
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -only-testing:SoloCodeAppTests/ComposerTodoOverlayStateTests -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests -only-testing:SoloCodeAppTests/TodoStoreTests -only-testing:SoloCodeAppTests/PlanBuildGuardTests`
- Commit previsto:
  - `fix(plan): remove legacy todo card from chat`
