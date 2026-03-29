## Bug Fix Record
- Categoria: A - Critico
- Bug: la timeline chat può tornare a mostrare una risposta unica monolitica con i tool separati a blocco, perdendo l'interleave reale `text/tool/text`
- Sintomo: durante o subito dopo lo stream, la riga assistant mostra un unico blocco risposta e una coda di tool invece della comparsa a segmenti
- Impatto: degrada il flusso core della chat, rende opaca la progressione del lavoro e reintroduce una regressione già corretta in precedenza
- Gravità: alta
- Steps to reproduce:
  1. aprire una conversazione con assistant message in streaming
  2. generare tool trace e testo interleavati
  3. lasciare che il renderer usi uno snapshot base monolitico mentre il runtime live è assente o più povero
- Risultato attuale: il renderer entra in fallback sintetico o usa uno snapshot povero, mantenendo il testo in un unico blocco
- Risultato atteso: il renderer deve recuperare il `ChatTurnState` più ricco disponibile e preservare i blocchi `primaryText/toolMarker/primaryText`
- Causa probabile: alcuni path recenti di refresh/performance possono lasciare la cella chat con uno snapshot base non aggiornato, mentre lo store persistito contiene già una timeline più ricca; i test coprivano i layer singoli ma non questa catena completa
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/*`
  - `App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Core/*`
  - test chat timeline correlati
- Non-scope:
  - refactor UI generale
  - modifiche a provider streaming non legate alla scelta del turn state
  - ristrutturazione della timeline interleaver oltre il fix necessario
- Moduli confinanti da verificare:
  - merge timeline streaming
  - restore da messaggio persistito
  - cache per assistant message id
  - fallback sintetico da trace
- Test da aggiungere o aggiornare:
  - restore del `ChatTurnState` da messaggio persistito interleavato
  - preferenza del turn store/cached rispetto al fallback sintetico
  - regressione end-to-end fino ai segmenti finali dell'interleaver
- Strategia di fix minimo:
  - introdurre un resolver dedicato che, prima del fallback sintetico, tenti il recupero del turn state dal messaggio persistito dello stesso assistant message
  - riusare un restore puro da `ChatMessage` per evitare divergenze fra hydration, display merge e adapter pipeline
- Verifica post-fix:
  - test unitari/di regressione sul resolver
  - test esistenti sulla timeline pipeline e sul synthetic fallback
- Commit previsto: `fix(chat): restore persisted interleaving before synthetic fallback`
