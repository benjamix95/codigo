# P1 — Path traversal via codeReviewSessionFilePath pubblico

## Bug Fix Record
- Categoria: B - Importante (Security)
- Bug: Il metodo pubblico `codeReviewSessionFilePath(sessionId:)` in `MCPSharedState+CodeReview.swift:66` non sanitizza il sessionId. Input come `../../etc/passwd` costruiscono path fuori dalla directory prevista.
- Sintomo: Un tool caller malevolo può leggere/scrivere file arbitrari sul filesystem.
- Impatto: Vulnerabilità di sicurezza — lettura/scrittura fuori sandbox.
- Gravità: P1
- Scope consentito: `MCPSharedState+CodeReview.swift` — metodo `codeReviewSessionFilePath`.
- Strategia di fix minimo: Applicare la stessa sanitizzazione di `validatedCodeReviewSessionFilePath` al metodo pubblico, o rendere il metodo privato e forzare l'uso di quello validato.
- Commit previsto: `fix(mcp-shared-state): sanitize sessionId in public file path method`
