# Plan Mode e Plan Panel

## Cos'è il Plan Mode

Il Plan Mode è una delle modalità operative di Codigo (insieme ad Agent, Agent Swarm, Code Review, IDE, MCP Server).
Si attiva selezionando `Plan` nella barra dei mode controls.

L'obiettivo è separare la **pianificazione** dall'**esecuzione**: prima l'AI analizza il problema e propone opzioni strutturate, poi l'utente sceglie e autorizza l'esecuzione. Questo riduce le modifiche inattese e permette di intervenire prima che il codice venga scritto.

---

## Fasi del flusso (PlanFlowPhase)

Il Plan Mode attraversa fasi sequenziali:

```
idle → analyzing → questioning → generating → proposalReady → readyToBuild → building
```

| Fase | Descrizione |
|------|-------------|
| `idle` | Nessun piano attivo. Punto di partenza e di ritorno dopo un build. |
| `analyzing` | **Fase 1** — L'AI analizza il codebase (indice semantico, file rilevanti). |
| `questioning` | **Fase 2** — L'AI ha generato domande di chiarimento; l'utente deve rispondere prima di procedere. |
| `generating` | **Fase 3** — L'AI sta generando le opzioni di piano strutturate. |
| `proposalReady` | Le opzioni sono pronte. L'utente può leggerle e sceglierne una. |
| `readyToBuild` | L'utente ha scelto un'opzione. Il build è sbloccato. |
| `building` | L'AI sta eseguendo il piano scelto (modifica file, comandi bash, tool calls). |

Il pulsante **Build** è abilitato solo nelle fasi `proposalReady` e `readyToBuild`. In tutte le altre fasi mostra una motivazione del perché è disabilitato.

---

## Stato di pianificazione (PlanningState)

Parallelo alle fasi, lo stato di pianificazione descrive cosa l'AI si aspetta dall'utente:

| Stato | Significato |
|-------|-------------|
| `idle` | Nessuna azione richiesta. |
| `awaitingClarification(questions)` | L'AI ha posto domande di chiarimento; l'utente deve rispondere. |
| `awaitingChoice(planContent, options)` | L'AI ha proposto opzioni; l'utente deve scegliere quale eseguire. |

---

## Struttura dell'output atteso dall'AI

Il Plan Mode impone all'AI un formato Markdown specifico per i suoi output, validato automaticamente dal `PlanOutputClassifier` e dal `PlanOptionsParser`.

### Domande di chiarimento

Blocco con heading `## Questions` (o varianti come `## Clarification questions`):

```markdown
## Questions

1. Vuoi mantenere la compatibilità con la versione precedente?
   a. Sì, piena retrocompatibilità
   b. No, possiamo rompere l'API
   c. Altro (specifica)

2. Quale database userai?
   a. SQLite
   b. PostgreSQL
```

Le domande di chiarimento hanno **priorità sulle opzioni**: se l'AI le include, il flusso va in `questioning` prima di procedere.

### Opzioni di piano

Blocco con heading `## Option N: Titolo` (o `## Approach N:`):

```markdown
## Option 1: Refactoring incrementale

Descrizione dell'approccio...

## Todo

- [ ] Creare nuovo modulo `DataLayer`
- [ ] Migrare i metodi esistenti
- [ ] Aggiornare i test

## Option 2: Riscrittura completa

Descrizione alternativa...

## Todo

- [ ] Eliminare il modulo legacy
- [ ] Implementare da zero con nuova architettura
```

Un'opzione è considerata **valida** ("todo-compliant") solo se:
1. Contiene un heading `## Todo` (case-insensitive).
2. Il `## Todo` ha almeno un elemento eseguibile (bullet, checklist, lista numerata).

Solo le opzioni valide abilitano il pulsante Build.

---

## Plan Panel

Il Plan Panel è il pannello laterale dedicato alla pianificazione. Si apre:

- **Automaticamente** quando il flusso entra in una fase attiva (es. `proposalReady`).
- **Manualmente** tramite shortcut da tastiera — in questo caso mostra anche lo storico dei piani.
- Tramite deep link interno all'app.

### Sezioni del Plan Panel

**Opzioni correnti**
Mostra le opzioni proposte dall'AI come card selezionabili. L'utente clicca su un'opzione per selezionarla, poi preme **Build** per avviare l'esecuzione.

**Summary Card**
Riepilogo del piano attivo: titolo, body descrittivo, eventuali blocchi Mermaid (diagrammi architetturali) e sezioni di cause/rationale/trade-off estratte automaticamente.

**Live Trace**
Durante il `building`, il Plan Panel mostra un trace in tempo reale di ogni operazione eseguita dall'AI:

| Tipo evento | Icona | Colore |
|-------------|-------|--------|
| Modifica file | `doc.text.fill` | verde (agentColor) |
| Comando bash | `terminal.fill` | arancione (warning) |
| MCP tool call | `wrench.and.screwdriver.fill` | blu (ideColor) |
| Ricerca web | `magnifyingglass` | azzurro (info) |
| Ricerca semantica | `brain` | azzurro (info) |
| Aggiornamento step | `list.bullet.rectangle` | viola (planColor) |
| Diagnostica lints | `exclamationmark.triangle.fill` | arancione (warning) |

Per ogni evento file vengono mostrati i delta `+N` righe aggiunte / `-N` rimosse. Espandendo la riga si può vedere il diff o l'output raw del comando.

**Storico piani (History)**
Visibile solo quando il panel è aperto manualmente via shortcut. Mostra gli ultimi piani generati per il workspace corrente (fino a 200 voci), ordinati per data di creazione. Ogni voce ricorda: titolo, markdown completo, opzioni, percorso scelto, numero di rebuild e data dell'ultimo build.

---

## Storico e persistenza (PlanHistoryStore)

I piani vengono salvati su file in `Application Support/CoderIDE/planHistory.json`.
`UserDefaults` viene usato solo per migrazione legacy e per le preferenze dei limiti.

Limiti configurabili (Settings → Behavior → Plan history limits), con default:

| Parametro | Limite |
|-----------|--------|
| Voci massime | 200 |
| Lunghezza markdown per piano | 65.536 caratteri |
| Opzioni persistite per piano | 8 |
| Lunghezza titolo | 120 caratteri |

Ogni voce è associata a:
- `conversationId` — la conversazione chat di origine.
- `contextId` / `contextFolderPath` — il workspace (cartella progetto).
- `sourceMessageId` — il messaggio chat che ha generato il piano.

È possibile duplicare, eliminare singole voci o cancellare tutto lo storico per un workspace.

---

## Policy del sistema prompt in Plan Mode

In Plan Mode, al sistema prompt dell'AI viene aggiunta una policy che forza un comportamento strutturato:

- Ogni turno ha un obiettivo preciso (analisi, domande, generazione, build) — non si mischiano.
- I passi devono essere eseguibili e verificabili, non teorici.
- Le dipendenze tra step devono essere esplicite.
- Non si combinano analisi + domande + opzioni in un'unica risposta.

Questo garantisce che il Plan Panel riceva sempre output nel formato atteso e che la classificazione automatica funzioni correttamente.

---

## Flusso completo — esempio

```
Utente digita il task in Plan Mode
          │
          ▼
    [analyzing] — l'AI legge il codebase rilevante
          │
          ▼
    [questioning] — (se necessario) l'AI chiede chiarimenti
          │     Utente risponde alle domande
          ▼
    [generating] — l'AI produce le opzioni strutturate (con ## Option + ## Todo)
          │
          ▼
    [proposalReady] — Plan Panel mostra le card con le opzioni
          │     Utente seleziona un'opzione
          ▼
    [readyToBuild] — Build abilitato
          │     Utente preme Build
          ▼
    [building] — Live Trace mostra ogni operazione in tempo reale
          │
          ▼
    [idle] — Build completato, piano salvato nello storico
```
