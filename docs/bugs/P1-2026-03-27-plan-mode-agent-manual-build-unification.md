# Bug Fix Record
- Categoria: A - Critico
- Bug: la modalità Plan pre-build seguiva ancora un ramo runtime separato dal main Agent path, con tool surface e timeline diversi.
- Sintomo:
  - il pre-build saltava la pipeline Agent e i subagent;
  - i messaggi di plan potevano essere sovrascritti o deviati nel panel;
  - le domande `plan_request_user_input` restavano panel-first invece che lineari in chat;
  - il `Build` partiva senza il messaggio utente finale richiesto e non ripuliva sempre il contesto di domande.
- Impatto: regressione sul flusso core del prodotto. `Plan` si comportava come planner separato invece che come chat Agent con gate manuale di esecuzione.
- Gravità: alta
- Steps to reproduce:
  1. Attivare `Plan`.
  2. Inviare un task multi-file.
  3. Osservare che discovery/questioning non passano per la stessa route/tool policy di Agent.
  4. Ottenere domande o piano e verificare che la chat non resti append-only.
  5. Premere `Build` e notare l’assenza del solo messaggio utente finale `Proceed with the plan.`.
- Risultato attuale:
  - `resolveMainChatSendExecutionRoute(...)` dava priorità al route `.planFlow`;
  - il prompt pre-build imponeva ancora discovery `Read/Glob/Grep` hard-coded;
  - `plan_request_user_input` rimpiazzava la bolla assistant con uno stato sintetico;
  - il build creava direttamente la pipeline senza il kickoff utente richiesto.
- Risultato atteso:
  - `Plan` pre-build usa la stessa route di `Agent` in base al transport disponibile;
  - tool e subagent restano quelli di Agent, ma con blocco fail-closed delle mutazioni fino al `Build`;
  - chat lineare e append-only, panel come mirror;
  - al `Build` spariscono le questions e compare solo `Proceed with the plan.` prima dell’esecuzione.
- Causa probabile:
  - branch runtime dedicato `planFlow`;
  - policy prompt pre-build separata dal contratto Agent;
  - gestione UI delle domande e del piano ancora appoggiata a replace/panel-first semantics;
  - kickoff build collegato solo alla pipeline, non al thread chat.
- Scope consentito:
  - routing send/runtime chat
  - policy/gating tool durante planning
  - sync plan chat/panel
  - kickoff build manuale
  - test mirati su route e guard
- Non-scope:
  - rimozione completa del codice legacy multi-turn plan inutilizzato
  - rifattorizzazioni generiche del panel o della pipeline review/debug
- Moduli confinanti da verificare:
  - chat send/runtime
  - task/policy gating
  - plan panel state mirroring
  - build kickoff nel thread corrente
- Test da aggiungere o aggiornare:
  - route resolution `Plan` -> `standardStream`/`agentPipeline`
  - plan build guard su tool mutanti e command execution
  - compatibilità provider Rust read-only plan
- Strategia di fix minimo:
  - rimuovere la priorità del route `.planFlow` pre-build;
  - preservare il contesto di chiarimento nel prompt lineare chat;
  - bloccare mutazioni durante planning con guard esplicito;
  - sincronizzare il piano finale dal normale stream Agent verso board/history/panel;
  - far partire il build con solo `Proceed with the plan.` nel thread attivo.
- Verifica post-fix:
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -only-testing:SoloCodeAppTests/ClaudeProviderIntegrationTests -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/PlanBuildGuardTests`
- Commit previsto:
  - `fix(plan): unify pre-build flow with agent runtime`
