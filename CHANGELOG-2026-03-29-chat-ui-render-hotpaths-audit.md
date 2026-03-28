# Changelog - 2026-03-29 - Chat UI render hotpaths audit

- Eseguito un audit del layer chat/UI per identificare i percorsi di rendering frequente e i colli di bottiglia principali.
- Analizzati `ChatPanelView`, l'header del thread, le celle messaggio, `ChatTurnView`, la timeline interleaver e il pannello subagent.
- Documentate in `output/bug-hunter/chat-ui-render-hotpaths-audit.md` le aree piu costose, in ordine di priorita, con file e funzioni coinvolte.
- Nessun file applicativo modificato in questo step.
- Nessun test eseguito: il lavoro svolto e stato di sola analisi/documentazione.
