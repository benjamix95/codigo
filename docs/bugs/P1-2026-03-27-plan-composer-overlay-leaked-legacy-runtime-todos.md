# Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: il composer overlay e la todo card del plan/build mostravano anche runtime todo legacy del thread, non solo i todo canonici del piano corrente.
- Sintomo:
  - durante `Plan` o subito dopo `Build` compariva un elenco lungo con task vecchi/non pertinenti;
  - il contatore dell’overlay risultava gonfiato rispetto ai soli step del piano;
  - il click su `Build` poteva sembrare creare una nuova card “sbagliata” in chat perché la card leggeva il bucket chat generale dei todo.
- Impatto: forte confusione UX; il piano corretto era presente, ma la UI lo mischiava con runtime todo storici dello stesso thread.
- Gravità: P1
- Steps to reproduce:
  1. Usare una conversazione con todo agent runtime preesistenti.
  2. Generare un nuovo plan con canonical todos propri.
  3. Osservare il composer overlay in `proposalReady/readyToBuild` o la todo card del turn assistant in build.
- Risultato attuale: overlay/card usano `displayTodosForChat(...)`, che include anche runtime todo non canonici del thread.
- Risultato atteso: in superficie `Plan` devono apparire solo i canonical todos del piano corrente, più eventuali placeholder operativi scoped allo stesso piano.
- Causa probabile:
  - `displayTodosForComposer(...)` partiva da `displayTodosForChat(...)`;
  - la todo card assistant usava lo stesso dataset generale, non un dataset plan-scoped.
- Scope consentito:
  - `TodoStore+Queries`
  - `ChatPanelView+PartD_MessageCell`
  - test `TodoStoreTests`
- Non-scope:
  - modifica del contenuto dei canonical plan todos
  - variazioni alla sidebar o al task panel globale
- Moduli confinanti da verificare:
  - composer overlay
  - turn todo card in chat
  - scoping canonical/runtime
- Test da aggiungere o aggiornare:
  - composer plan mode excludes legacy runtime todos
  - plan-scoped chat list excludes legacy runtime todos
- Strategia di fix minimo:
  - introdurre una query plan-scoped che restituisce canonical todos del piano corrente;
  - opzionalmente aggiungere solo placeholder operativi scoped;
  - usare quel dataset nel composer overlay e nella todo card plan/build.
- Verifica post-fix:
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -only-testing:SoloCodeAppTests/TodoStoreTests -only-testing:SoloCodeAppTests/PlanBuildGuardTests -only-testing:SoloCodeAppTests/ClaudeProviderIntegrationTests -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests`
- Commit previsto:
  - `fix(plan): scope composer and chat plan todos to canonical items`
