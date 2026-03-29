# Bug Fix Record — 2026-03-29 — Sezioni sub-agent collassabili per ondata di lancio

- **Categoria:** B — Importante ma non bloccante
- **Bug:** la timeline chat creava una sola sezione collassabile per tutti i sub-agent completati del turno, invece di mostrare più sezioni coerenti con i lanci separati o paralleli.
- **Sintomo:** in chat non si vedono sezioni distinte “come per i tools”; anche sub-agent lanciati in momenti diversi finiscono tutti nello stesso blocco.
- **Impatto:** timeline poco leggibile, perdita della struttura dei lanci separati, sezione finale troppo grossa e meno utile da collassare.
- **Gravità:** Media
- **Steps to reproduce:**
  1. Lanciare più sub-agent in due momenti distinti nello stesso turno.
  2. Lasciarli completare.
  3. Guardare la timeline del messaggio assistente.
- **Risultato attuale:** tutti i terminali vengono raccolti in un’unica sezione `completedSubagentsGroup`.
- **Risultato atteso:** più sezioni collassabili, una per ogni ondata di lancio; una sezione può contenere 1, 2 o più sub-agent se lanciati nello stesso momento.
- **Causa probabile:** il builder dei gruppi terminali aggregava tutti i candidati del turno senza una fase di split per coorti cronologiche.
- **Scope consentito:** interleaver timeline chat e test di interleaving sub-agent.
- **Non-scope:** runtime swarm, persistenza snapshot, UI delle card snapshot, protocollo provider.
- **Moduli confinanti da verificare:**
  - `ChatTurnTimelineInterleaver`
  - `ChatTurnTimelineInterleaver+CompletedSubagents`
  - test `ChatTimelineInterleavingSubagentTests`
- **Test da aggiungere o aggiornare:**
  - gruppi multipli per lanci separati
  - gruppo singolo per lanci nella stessa ondata
  - comportamento preesistente su anchor e stato misto
- **Strategia di fix minimo:**
  - sostituire il singolo `completedSubagentGroup(...)` con `completedSubagentGroups(...)`
  - dedurre le coorti da `sequence` e boundary narrativi nei `blocks`
  - lasciare invariata la view della sezione, riusandola più volte nella timeline
- **Verifica post-fix:**
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTimelineInterleavingSubagentTests`
- **Commit previsto:** `fix(chat): split completed subagent sections by launch wave`
