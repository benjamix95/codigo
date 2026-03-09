# 2026-03-09 — Audit della pipeline di code review

## Obiettivo
- verificare se la pipeline di code review, audit, BugHunter, policy, MCP e patch workflow sia deterministica, realmente verificante e sufficientemente rigorosa
- distinguere tra controlli duri, euristiche locali e verifiche affidate al modello
- registrare i bug e i rischi per priorita'

## Metodo
- analisi statica del codice di `Engine/CoderEngine`, `Tools/CoderIDEMCPServer` e `App/SoloCodeApp`
- analisi parallela in 8 filoni: architettura end-to-end, audit subsystem, BugHunter, verification dei finding, patch workflow, policy enforcement, MCP routing, copertura test
- confronto tra implementazione, handler MCP, shared state, provider runtime e test disponibili
- tentativi di esecuzione test via `xcodebuild` sul workspace `Solo Code.xcworkspace`

## Limiti della verifica
- non e' stato eseguito un test end-to-end completo della pipeline review reale, perche' gli scheme disponibili non espongono in questo ambiente un target test eseguibile per `CoderEngineTests`
- la valutazione finale combina quindi:
  - evidenza diretta dal codice
  - evidenza dai test presenti nel repo
  - assenza di prove dove la suite non copre il comportamento composito

## Executive Summary
La pipeline non e' un sistema "a sentimento", ma neppure un sistema formalmente rigoroso end-to-end. I mattoni di base sono generalmente buoni: validazioni input, session state, store condiviso, naming tool, collisioni MCP, alcune guardrail del provider e molta parte dell'audit statico locale. Il problema serio e' nel significato operativo di parole come `verified`, `autofix applied` e, in parte, "policy enforced": in diversi punti il nome della feature comunica una garanzia piu' forte di quella effettivamente implementata.

Il verdetto sintetico e':
- determinismo alto: validazione handler, session state, naming/routing catalog, parte del runtime MCP, persistenza plan
- determinismo medio: audit heuristici, event mapping MCP, tool surface esposta al modello, stato condiviso legacy, BugHunter queue/hook
- determinismo basso: output LLM, parsing task multi-swarm, promozione candidate -> verified, semantica reale di alcuni success path autofix

## Verdetto per sottosistema

| Sottosistema | Determinismo | Rigidita' della verifica | Note |
| --- | --- | --- | --- |
| Handler MCP review | Alto | Alta su input e session resolution | Buone validazioni, duplicati e scope difesi |
| Session state review | Alto | Alta | Actor/state model coerente |
| Audit subsystem | Medio | Media | Molto rule-based, ma diversi check sono euristici e non dimostrativi |
| Multi-swarm parsing | Basso-Medio | Bassa | Dipende dal formato LLM e da euristiche testuali |
| Candidate verification | Basso | Bassa | Il nome `verified` e' oggi fuorviante |
| BugHunter orchestration | Medio | Media-Bassa | E' un orchestratore sopra review, non un motore indipendente forte |
| Patch workflow review | Medio-Basso | Bassa-Media | Preview con diff presente, apply con garanzie deboli |
| Policy enforcement | Medio | Mista | Budget e subagent policy sono hard, molte altre regole sono prompt-only |
| MCP routing/runtime | Medio-Alto | Media-Alta | Dispatch solido, surface tool visibile al modello non sempre stabile |
| Copertura test | Media | Media | Buona sui mattoni, debole sull'orchestrazione end-to-end |

## Findings prioritizzati

### P0
1. `ReviewCandidateVerificationService` puo' promuovere finding come `verified` con controlli troppo deboli.
   - Un candidate senza `lineNumber` puo' passare se `evidence` compare in qualche punto del file.
   - Il metodo `semantic_risk_match` e' lessicale, non prova reachability, exploitability o causalita'.
   - Impatto: alto rischio di falsi positivi marchiati come verificati.

### P1
1. BugHunter puo' dichiarare successo dell'autofix senza dimostrare che la patch sia stata davvero preparata o applicata.
2. BugHunter salva il commit primario in forma incoerente rispetto alla deduplica, con rischio di run duplicati o non deduplicati correttamente.
3. `review_apply_patch` e il patch workflow review non usano le stesse garanzie forti del transaction engine e non espongono abbastanza explainability all'utente.
4. La surface MCP visibile al modello dipende dal warmup best-effort e da un registry globale condiviso, quindi non e' pienamente stabile tra request/sessioni.
5. `policy_ack` e gran parte delle policy bundle sono soprattutto testo/prompt guidance, non gate hard prima dei tool.

### P2
1. Diversi audit sono utili come triage ma non dimostrativi:
   - `securityDataflow` usa co-occorrenza source/sink su finestre di righe
   - `bugNilCrashPaths` e' rumoroso
   - `bugTestImpact` si basa su naming conventions
   - `securitySupplyChain` usa matcher testuali deboli
2. `ProviderToolEventMapper` e' robusto per compatibilita', ma ricostruisce parte del significato da payload eterogenei con euristiche.
3. Gli hook queue di BugHunter hanno rischio di perdita eventi in scenari di concorrenza o crash.
4. La copertura test e' forte sui componenti isolati ma debole sui flussi completi review -> provider -> findings -> patch/apply -> outcome.

## Dove il sistema verifica davvero
- validazione degli input MCP e risoluzione sessioni
- deduplica di alcuni comandi e protezioni su `session_id`
- session state actor e crescita di `mutationSequence`
- naming/collision handling dei tool MCP nel catalogo
- parti del runtime tool con dispatch ordinato e fallback noti
- diversi test su snapshot store, redaction output, diff summary e consistency MCP
- budget per round, read-only policy e alcune guardrail subagent nel provider

## Dove il sistema usa euristiche o segnali indiretti
- estrazione dei task da output LLM multi-swarm
- rilevazione "issues vs clean" da testo di re-review
- verifica dei candidate via `file_evidence_search`, `line_evidence_match`, `semantic_risk_match`
- clusterizzazione/correlazione di alcuni finding audit
- event mapping MCP quando il provider produce payload diversi
- gran parte della semantica "security/bug found" negli audit piu' avanzati

## Dove il nome della feature e' piu' forte della garanzia reale
- `verified`
  - oggi significa soprattutto "ha passato un sanity check locale", non "bug/vulnerability dimostrato"
- `autofix applied`
  - in alcuni path BugHunter puo' essere restituito anche senza prova forte che il workflow patch sia davvero riuscito
- `policy_ack`
  - tracciato e utile, ma non e' una precondizione hard universale prima dell'uso tool

## Patch workflow: risposta puntuale alla domanda su diff e spiegazione
- `review_preview_patch` espone davvero un diff preview.
- `review_preview_patch` non espone in modo sufficiente il razionale del finding che la patch intende risolvere.
- `review_apply_patch` non mostra diff ne' una spiegazione del bug/security finding prima dell'applicazione.
- Il path review non sembra passare dalle stesse difese forti del transaction engine (`manifest validation`, `blast radius`, rollback strutturato, risk gate forte).

## Determinismo end-to-end
Non e' corretto descrivere l'intera pipeline come deterministica.

Le fonti principali di non-determinismo sono:
- output LLM e parsing dei task di review
- backend `auto` e tool surface MCP dipendente dal warmup
- queue/file shared state con semantiche vicine a `at-least-once`, non `exactly-once`
- euristiche di mapping payload e verifica candidate
- doppia fonte di verita' tra registry live, snapshot persistiti e stato MCP

## Copertura test: cosa c'e' e cosa manca

### Copertura buona
- handler MCP review
- session state review
- snapshot store e command store review
- parsing/normalizzazione multi-swarm
- diff summary su repo reale
- audit advanced tests locali
- protocollo `policy_ack` e lifecycle subagent
- consistency MCP
- persistenza BugHunter e filtro autofix

### Gap rilevanti
- nessun end-to-end forte `review_start -> analysis -> findings -> final state`
- copertura quasi assente del patch workflow review
- copertura debole o assente degli handler BugHunter e del loro workflow reale
- poca o nessuna prova di concorrenza/locking vero
- niente forte dimostrazione del success path MCP reale con server/fake server integrato

## Bug Fix Record sintetico del task corrente
- Categoria: A/B mista
- Bug: la pipeline di code review usa nomi e stati che in piu' punti promettono verifiche piu' forti di quelle effettivamente implementate
- Sintomo: `verified`, `autofix applied`, `policy enforced` e patch workflow possono apparire piu' affidabili di quanto il codice dimostri
- Impatto: falsi positivi, falsa sicurezza operativa, ridotta tracciabilita' delle garanzie reali
- Gravita': P0/P1 a seconda del sottosistema
- Steps to reproduce:
  1. Leggere i path di verification, patch workflow, BugHunter e policy bundle.
  2. Confrontare nomi esposti all'utente con le condizioni effettivamente controllate dal codice.
  3. Cercare test end-to-end che dimostrino le garanzie dichiarate.
- Risultato attuale: molte guardrail esistono, ma non sempre coincidono con una verifica rigorosa del comportamento dichiarato.
- Risultato atteso: ogni etichetta utente rilevante deve corrispondere a un gate forte, spiegabile e testato.
- Causa probabile: stratificazione progressiva del sistema con mix di controlli duri, euristiche locali e affidamento al modello.
- Scope consentito: review pipeline, audit, BugHunter, provider policy/runtime, MCP, patch workflow, test.
- Non-scope: feature unrelated, refactor generali, UI cosmetica.
- Moduli confinanti da verificare: shared state, lock/queue, event mapping, transaction engine, review handlers, BugHunter handlers.
- Test da aggiungere o aggiornare: end-to-end review pipeline, verification service, patch workflow review, BugHunter handlers, MCP success path, stale reclaim/hook queue.
- Strategia di fix minimo: stringere i gate nei punti P0/P1 prima di qualsiasi ampliamento architetturale.
- Verifica post-fix: test di regressione mirati e smoke suite su review, patch workflow, BugHunter e MCP routing.
- Commit previsto: `docs(review): add code review pipeline audit report`

## Raccomandazioni operative
1. Rinominare o irrigidire `verified`.
   - Se resta il nome attuale, la promozione deve richiedere prove piu' forti.
2. Rendere gli esiti BugHunter/autofix dipendenti da uno stato finale verificato del patch workflow.
3. Portare `review_apply_patch` sul transaction engine o allinearne i gate.
4. Rendere il `policy_ack` una precondizione hard dove il prodotto afferma esplicitamente di richiederlo.
5. Aggiungere una suite end-to-end minima che copra il percorso reale e non solo i singoli mattoni.

## File chiave analizzati
- `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/ReviewPipelineCoordinator.swift`
- `Engine/CoderEngine/Sources/CodeReview/Verification/ReviewCandidateVerificationService.swift`
- `Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+PatchWorkflow.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter/BugHunterHandler+Commands.swift`
- `Engine/CoderEngine/Sources/Policy/InstructionPolicyBundle.swift`
- `Engine/CoderEngine/Sources/Providers/Core/ToolEnabledLLMProvider/Send/ToolEnabledLLMProvider+SendRoundProcessing.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/MCPSessionManager.swift`
- `Engine/CoderEngine/Sources/Providers/Core/ProviderToolEventMapper/ProviderToolEventMapper+MapMCP.swift`

## Esito finale
La pipeline ha una buona ossatura ingegneristica, ma oggi non e' corretto presentarla come completamente deterministica o rigorosamente verificante in ogni suo tratto. Dove esistono gate hard, funzionano bene. Dove il sistema passa da output LLM, euristiche lessicali o messaggi di successo scollegati da una prova finale, la garanzia reale scende in modo significativo.
