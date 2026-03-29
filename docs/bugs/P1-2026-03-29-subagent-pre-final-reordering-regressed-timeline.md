# [P1] Il riordino “subagent prima del testo finale” rompe la timeline cronologica

## Bug Fix Record
- Categoria: A
- Bug: il pass che forza le card subagent prima dell'ultimo testo finale altera l'ordine cronologico dei segmenti e può riportare la timeline verso un comportamento percepito come monolitico.
- Sintomo: card subagent spostate artificialmente rispetto alle operazioni reali; blocchi testuali e operativi non più coerenti con la cronologia del turno.
- Impatto: regressione in un'area fragile già sistemata con difficoltà; la timeline del turno perde affidabilità.
- Gravità: alta
- Steps to reproduce:
  1. Aprire un turno con più blocchi di testo e subagent.
  2. Applicare un riordino che sposta i subagent trailing prima dell'ultimo testo.
  3. Osservare che la cronologia non segue più l'ordine naturale di `sequence`/operazioni.
- Risultato attuale: i subagent possono essere anticipati rispetto alla loro posizione cronologica reale.
- Risultato atteso: i subagent restano ancorati alle operazioni via `swarm_id`/trace sequence; senza anchor restano in coda cronologica, senza manipolazioni speciali.
- Causa probabile: il post-processing introdotto dopo il sort dell’interleaver ignorava l’ordine cronologico originale dei segmenti.
- Scope consentito: interleaver timeline, test di regressione, footer finale task.
- Non-scope: rendering delle card subagent, sidebar, composer, diff file edit.
- Moduli confinanti da verificare: synthetic timeline fallback, live card anchor, snapshot anchor, final footer placement.
- Test da aggiungere o aggiornare: più regressioni su subagent anchor e preservazione dei blocchi testuali multipli.
- Strategia di fix minimo: rimuovere il riordino forzato, mantenere il footer finale in basso e blindare i casi con test.
- Verifica post-fix: test mirati su interleaver e footer placement.
- Commit previsto: `fix(chat): restore anchored subagent timeline ordering`
