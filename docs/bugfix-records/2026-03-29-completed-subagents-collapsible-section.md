# Bug Fix Record — 2026-03-29 — Sezione collassabile per sub-agent completati

- **Categoria:** B — Importante ma non bloccante
- **Bug:** i sub-agent terminali restavano come card sparse nella timeline chat e non venivano raccolti in una sezione compatta; in presenza di stato live e snapshot persistiti lo stesso swarm poteva anche comparire in forma non aggiornata.
- **Sintomo:** la chat si sporca con card finali distribuite nel turno; durante stati misti il layout perde pulizia e, se esiste uno snapshot persistito dello stesso swarm ancora `running`, si rischia di mostrare uno stato terminale stale.
- **Impatto:** UX degradata sulla timeline, lettura cronologica più rumorosa, rischio di rappresentazione incoerente dello stato dei sub-agent.
- **Gravità:** Media
- **Steps to reproduce:**
  1. Avviare un turno con più sub-agent.
  2. Lasciarne terminare uno mentre un altro continua a girare.
  3. Osservare la timeline chat del messaggio assistente.
- **Risultato attuale:** i sub-agent completati/falliti restano come card autonome nella timeline; gli snapshot persistiti non sono raccolti e possono competere con lo stato live.
- **Risultato atteso:** i sub-agent `running` restano inline; i sub-agent `completed` e `failed` vengono raggruppati in una sola sezione collassabile, con deduplica che privilegia lo stato più aggiornato.
- **Causa probabile:** l’interleaver trattava live card e snapshot come segmenti indipendenti senza un modello aggregato per i terminali e senza una precedenza esplicita tra snapshot persistiti e stato live.
- **Scope consentito:** interleaver timeline chat, modello segmenti interleaved, rendering UI della timeline, fallback legacy di presentazione snapshot, test di regressione correlati.
- **Non-scope:** persistenza `subagentCards`, runtime swarm, protocollo eventi, pipeline Rust, store conversazioni.
- **Moduli confinanti da verificare:**
  - `ChatTurnTimelineInterleaver`
  - `ChatTurnView` / rendering segmenti
  - fallback snapshot in `ChatPanelView+PartE_TaskLifecycle+UI`
- **Test da aggiungere o aggiornare:**
  - ancoraggio cronologico del gruppo terminale
  - stato misto `running` + terminali
  - deduplica live vs snapshot
  - stato iniziale collassato della nuova sezione
- **Strategia di fix minimo:**
  - introdurre un gruppo dedicato `completedSubagentsGroup`
  - mantenere inline solo i live `running`
  - trasformare i terminali in un unico segmento collassabile
  - preferire lo stato live terminale o live running agli snapshot persistiti dello stesso swarm
- **Verifica post-fix:**
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTimelineInterleavingSubagentTests -only-testing:SoloCodeAppTests/ChatTimelineInterleavingToolGroupingTests -only-testing:SoloCodeAppTests/ChatTurnCompletedSubagentsGroupPresentationTests`
- **Commit previsto:** `fix(chat): group completed subagents into collapsible timeline section`

## Bug trovati in questo intervento

### P1 — Sub-agent terminali sparsi nella timeline
- **Stato:** Risolto
- **Nota:** la chat non rimaneva pulita perché ogni card finale occupava spazio autonomo invece di finire in una sezione comprimibile.

### P1 — Snapshot persistito stale può competere con il live state
- **Stato:** Risolto
- **Nota:** se esisteva uno snapshot dello stesso `swarmId` mentre il live card era ancora attivo, il gruppo terminale poteva mostrare un risultato non aggiornato. La deduplica ora esclude gli snapshot di swarm ancora `running` e preferisce il live terminale quando esiste.
