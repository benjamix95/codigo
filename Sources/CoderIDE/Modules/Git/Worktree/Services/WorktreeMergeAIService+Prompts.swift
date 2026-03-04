import Foundation

extension WorktreeMergeAIService {
    func conflictResolutionPrompt(
        sourceBranch: String,
        targetBranch: String,
        conflictedFiles: [String]
    ) -> String {
        let files = conflictedFiles.isEmpty
            ? "- (nessun file esplicito, rileva con git status)"
            : conflictedFiles.map { "- \($0)" }.joined(separator: "\n")
        return """
        Sei in una pipeline di merge automatico assistito.
        Obiettivo: risolvere i conflitti in modo semantico preservando comportamento e funzionalità di entrambi i rami.

        Branch sorgente: \(sourceBranch)
        Branch target: \(targetBranch)

        File in conflitto:
        \(files)

        Regole obbligatorie:
        - Analizza entrambi i lati del conflitto prima di modificare.
        - Integra le parti utili di entrambi i rami quando compatibili.
        - Non usare risoluzioni brutali "ours/theirs" se non strettamente necessario.
        - Mantieni codice compilabile e coerente.
        - Dopo le modifiche, verifica che non esistano più conflitti git.
        - Se restano conflitti non risolvibili in sicurezza, spiega chiaramente il blocco.

        Esegui direttamente le modifiche e i controlli necessari.
        """
    }

    func qualityFixPrompt(
        stage: String,
        commandDescription: String,
        failedOutput: String,
        attempt: Int,
        maxAttempts: Int
    ) -> String {
        let truncated = String(failedOutput.prefix(16_000))
        return """
        Quality gate \(stage) fallito.
        Devi correggere il progetto e portare i test in verde.

        Comando test: \(commandDescription)
        Tentativo: \(attempt)/\(maxAttempts)

        Output errore test:
        \(truncated)

        Regole:
        - Applica fix minimi e sicuri.
        - Preserva il comportamento richiesto.
        - Riesegui il comando test fino a pass.
        - Se non riesci, lascia una diagnosi precisa.
        """
    }
}
