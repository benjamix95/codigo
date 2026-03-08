# P1 - Review panel chat troppo generica su bug/security e output markdown degradato

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: la chat dedicata del code review panel parte con un prompt troppo generico e renderizza molte risposte assistant/system non strutturate come semplice `Text`, degradando sia il focus sui bug sia la leggibilità dell'output.
- Sintomo: aprendo una nuova conversazione nella review chat, il modello può rispondere come assistente generico invece che come bug hunter/security reviewer; inoltre heading, liste e blocchi markdown appaiono come plain text non formattato.
- Impatto: minor precisione nella ricerca di bug/regressioni/security issue e ridotta leggibilità delle risposte nel pannello review.
- Gravità: alta lato review workflow, media lato stabilità applicativa
- Steps to reproduce:
  1. Aprire il pannello Code Review e selezionare la tab Chat.
  2. Avviare una conversazione libera, per esempio chiedendo di trovare bug o problemi di sicurezza.
  3. Osservare che il prompt della chat review non impone con sufficiente forza focus bug/security/tooling.
  4. Osservare che una risposta assistant con headings, liste o blocchi markdown viene mostrata come testo semplice nel fallback del bubble review.
- Risultato attuale: il comportamento della review chat dipende troppo dal modello scelto; il testo senza `presentation.sections` dedicate non viene renderizzato con il markdown renderer dell'app.
- Risultato atteso: la review chat deve partire con istruzioni esplicite da bug hunter/security reviewer con enfasi sugli strumenti disponibili e deve mostrare output markdown leggibile anche nel fallback non strutturato.
- Causa probabile: `ReviewPanelCoordinator.chatContextPrompt(...)` era limitata a una consegna molto generica; `ReviewPanelChatBubble+Helpers.swift` usava `Text(message.content)` per i messaggi assistant/system non trasformati in sezioni strutturate.
- Scope consentito: prompt builder review chat, bubble rendering review chat, tab chat review, test unitari review chat, docs bug/changelog.
- Non-scope: main chat agent, pipeline swarm principale, tool runtime globale, summary structured cards della review.
- Moduli confinanti da verificare: `ReviewPanelCoordinator+Prompts.swift`, `ReviewPanelChatBubble.swift`, `ReviewPanelChatBubble+Helpers.swift`, `ReviewPanelChatTab.swift`, test review chat.
- Test da aggiungere o aggiornare: coverage per il prompt della review chat e verifica regressiva che la review chat continui a produrre structured sections per summary/review run.
- Strategia di fix minimo: rafforzare solo il prompt della review chat e riusare `MarkdownContentView` già presente nel progetto per il fallback visuale del bubble review.
- Verifica post-fix:
  1. Eseguire i test `ReviewPanelChatStructuredContentTests`.
  2. Eseguire i test `ReviewPanelLifecycleE2ETests`.
  3. Aprire manualmente la review chat e chiedere una review bug/security verificando headings, liste e code fence nel bubble assistant.
- Commit previsto: `fix(review-chat): enforce bug/security focus and markdown rendering`
