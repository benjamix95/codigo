# Bug Fix Record — 2026-03-29 — Sezioni live sub-agents ancorate dalla creazione

- **Categoria:** B — Importante ma non bloccante
- **Bug:** le sezioni sub-agent nella timeline nascevano solo a completamento oppure lasciavano le live card fuori sezione, quindi il turno non restava pulito durante l’esecuzione.
- **Sintomo:** i sub-agent partono come card sciolte; la sezione non compare subito; il nome non è allineato alla richiesta utente; il collasso automatico scatta solo a fine snapshot e non sul gruppo live.
- **Impatto:** timeline incoerente rispetto ai tool group, scorrimento più rumoroso e perdita di ancoraggio visivo durante l’esecuzione dei sub-agent.
- **Gravità:** Media
- **Steps to reproduce:**
  1. Lanciare uno o più sub-agent in chat.
  2. Osservare la timeline mentre sono ancora `running`.
  3. Verificare se appaiono subito dentro una sezione dedicata.
- **Risultato attuale:** le live card possono comparire fuori sezione; la sezione non è garantita fin dall’inizio; il titolo non è `sub-agents`.
- **Risultato atteso:** appena nasce un sub-agent, compare subito una sezione `sub-agents` ancorata alla sua wave; le entry live restano dentro la sezione; quando tutte le entry del gruppo diventano terminali, la sezione si auto-collassa.
- **Causa probabile:** il modello del gruppo era pensato solo per snapshot terminali e non per entry miste `running` + terminali.
- **Scope consentito:** modello gruppo timeline sub-agent, interleaver, view della sezione, test di presentazione/interleaving.
- **Non-scope:** protocollo provider, runtime swarm, persistenza snapshot, pannello swarm separato.
- **Moduli confinanti da verificare:**
  - `ChatTurnCompletedSubagentsGroup*`
  - `ChatTurnTimelineInterleaver`
  - `ChatTurnSegmentView`
- **Test da aggiungere o aggiornare:**
  - sezione live creata subito con entry `running`
  - auto-collapse quando il gruppo finisce
  - titolo sezione `sub-agents`
  - wave separate vs stessa wave
- **Strategia di fix minimo:**
  - estendere il gruppo per contenere entry miste live/snapshot
  - rendere la sezione il contenitore unico anche per i `running`
  - auto-presentazione: espansa se c’è almeno un `running`, collassata appena il gruppo si chiude
- **Verifica post-fix:**
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTimelineInterleavingSubagentTests -only-testing:SoloCodeAppTests/ChatTurnCompletedSubagentsGroupPresentationTests`
- **Commit previsto:** `fix(chat): anchor live subagents inside timeline sections`
