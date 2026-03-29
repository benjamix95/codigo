# [P2] Footer `Task completed` in alto e card subagent dopo la risposta finale

## Bug Fix Record
- Categoria: B
- Bug: il footer finale del task appare nella chrome alta della schermata e le card subagent possono finire sotto l'ultimo testo dell'assistente.
- Sintomo: `Task completed` appare sopra la chat; alcune card subagent snapshot restano dopo la risposta finale del modello.
- Impatto: la gerarchia del turno è incoerente; la risposta finale non è più davvero finale.
- Gravità: media
- Steps to reproduce:
  1. Completare un task con risposta finale dell'assistente.
  2. Osservare la UI: `Task completed` compare in alto.
  3. In alcuni turni con subagent snapshot senza ancoraggio trace, osservare card subagent sotto il testo finale.
- Risultato attuale: footer task fuori dalla timeline bassa; subagent snapshot talvolta in coda al turno.
- Risultato atteso: footer finale sotto la chat; subagent sempre prima dell'ultimo testo finale.
- Causa probabile: il footer finale veniva renderizzato nel runtime chrome; le snapshot subagent senza `sequence` propria usavano fallback in coda.
- Scope consentito: root layout della chat, interleaver del turno, policy pure di placement.
- Non-scope: layout visuale del footer, stile card subagent, sidebar, composer.
- Moduli confinanti da verificare: `ChatTurnTimelineInterleaver`, `RootLayout`, test interleaving.
- Test da aggiungere o aggiornare: regressione interleaver per snapshot prima del testo finale; test policy footer sotto i messaggi.
- Strategia di fix minimo: spostare il footer sotto l'area messaggi e introdurre un riordino post-sort che evita subagent sotto l'ultimo blocco di testo.
- Verifica post-fix: test unitari mirati.
- Commit previsto: `fix(chat): keep task footer and subagents below final answer`
