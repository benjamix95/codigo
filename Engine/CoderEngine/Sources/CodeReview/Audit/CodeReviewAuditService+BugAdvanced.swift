import Foundation

extension CodeReviewAuditService {
    static func runBugNilCrashPathsAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        let patterns: [(String, FindingSeverity, String, String, Double)] = [
            ("!", .warning, "Possibile crash path da force unwrap.", "Sostituisci con guard/if let o fallback esplicito.", 0.62),
            ("try!", .warning, "Possibile crash path da force-try.", "Gestisci l'errore in modo esplicito.", 0.84),
            (" as! ", .warning, "Possibile crash path da cast forzato.", "Usa cast sicuro e validazione dell'input.", 0.79),
            ("first!", .warning, "Accesso forzato al primo elemento.", "Verifica emptiness prima dell'accesso.", 0.72),
            ("last!", .warning, "Accesso forzato all'ultimo elemento.", "Verifica emptiness prima dell'accesso.", 0.72),
        ]
        return patternBugAudit(
            scopeFiles: scopeFiles,
            workspacePath: workspacePath,
            patterns: patterns,
            sourceTool: ReviewAuditToolName.bugNilCrashPaths,
            summaryWhenEmpty: "Nessun crash path evidente da optional/indexing rilevato.",
            summaryWhenNonEmpty: "Rilevati crash path potenziali da optional o cast forzati."
        )
    }

    static func runBugStateMachineAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        var findings: [CodeReviewFinding] = []
        for file in scopeFiles {
            guard let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }
            let joined = lines.joined(separator: "\n").lowercased()
            guard joined.contains("enum") && joined.contains("state") else { continue }
            let mutationLines = lines.enumerated().filter { _, line in
                let lower = line.lowercased()
                return lower.contains("state = .") || lower.contains(".state =")
            }
            if mutationLines.count >= 3 && !joined.contains("switch state") && !joined.contains("guard state") {
                findings.append(
                    makeFinding(
                        severity: .suggestion,
                        category: .regression,
                        origin: .bugHunter,
                        filePath: file,
                        lineNumber: mutationLines.first.map { $0.offset + 1 },
                        message: "State machine con più mutazioni senza guard/switch espliciti.",
                        suggestedFix: "Rendi esplicite le transizioni di stato e aggiungi guardie o assert sui passaggi invalidi.",
                        confidence: 0.67,
                        evidence: "state mutations: \(mutationLines.count)",
                        sourceTool: ReviewAuditToolName.bugStateMachine,
                        blocking: false
                    )
                )
            }
        }
        return (
            deduplicate(findings),
            !scopeFiles.isEmpty,
            findings.isEmpty ? "Nessuna anomalia evidente di state machine." : "Rilevate state transition sospette.",
            [],
            ["signal_type": "semantic", "verification_hint": "Conferma le transizioni ammesse e cerca stati non raggiungibili o non protetti", "promotion_gate": "strict_verified"]
        )
    }

    static func runBugConcurrencyAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        let patterns: [(String, FindingSeverity, String, String, Double)] = [
            ("dispatchqueue.main.sync", .critical, "Rischio deadlock su main thread.", "Evita sync sulla main queue o riprogetta il flusso.", 0.93),
            ("task.detached", .warning, "Task detached da verificare per actor isolation e lifetime.", "Controlla isolamento, cancellation e accesso a stato condiviso.", 0.73),
            ("nslock()", .suggestion, "Uso lock manuale: verifica ownership e ordine di acquisizione.", "Documenta o centralizza la disciplina dei lock.", 0.56),
        ]
        return patternBugAudit(
            scopeFiles: scopeFiles,
            workspacePath: workspacePath,
            patterns: patterns,
            sourceTool: ReviewAuditToolName.bugConcurrency,
            summaryWhenEmpty: "Nessun pattern di concurrency ad alto rischio rilevato.",
            summaryWhenNonEmpty: "Rilevati pattern di concurrency/deadlock da verificare."
        )
    }

    static func runBugErrorHandlingAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        let patterns: [(String, FindingSeverity, String, String, Double)] = [
            ("catch {}", .warning, "Catch vuoto che sopprime il failure.", "Registra, propaga o convertilo in fallback esplicito.", 0.88),
            ("try?", .suggestion, "Uso di try? da verificare: può nascondere failure reali.", "Valuta gestione esplicita dell'errore nei path critici.", 0.62),
            ("assertionfailure(", .suggestion, "Failure path non produttivo o potenzialmente non testato.", "Verifica il comportamento in release e nei test.", 0.58),
        ]
        return patternBugAudit(
            scopeFiles: scopeFiles,
            workspacePath: workspacePath,
            patterns: patterns,
            sourceTool: ReviewAuditToolName.bugErrorHandling,
            summaryWhenEmpty: "Nessun anti-pattern evidente di error handling.",
            summaryWhenNonEmpty: "Rilevati anti-pattern di gestione errori o fallback silenziosi."
        )
    }

    static func runBugAPIContractsAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        var findings: [CodeReviewFinding] = []
        for file in scopeFiles {
            guard let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }
            for (index, line) in lines.enumerated() {
                let lower = line.lowercased()
                let isPublicContract = lower.contains("public func") || lower.contains("open func") || lower.contains("protocol ")
                let isStubbed = lower.contains("fatalerror(\"todo") || lower.contains("fatalerror(\"not implemented") || lower.contains("preconditionfailure(")
                guard isPublicContract && isStubbed else { continue }
                findings.append(
                    makeFinding(
                        severity: .warning,
                        category: .correctness,
                        origin: .bugHunter,
                        filePath: file,
                        lineNumber: index + 1,
                        message: "API o contratto pubblico con stub o failure esplicita nel path corrente.",
                        suggestedFix: "Completa l'implementazione o limita la visibilità finché il contratto non è stabile.",
                        confidence: 0.83,
                        evidence: line.trimmingCharacters(in: .whitespacesAndNewlines),
                        sourceTool: ReviewAuditToolName.bugAPIContracts,
                        blocking: false
                    )
                )
            }
        }
        return (
            deduplicate(findings),
            !scopeFiles.isEmpty,
            findings.isEmpty ? "Nessun contract smell evidente nelle API scoped." : "Rilevati contract smell nelle API pubbliche o protocol.",
            [],
            ["signal_type": "semantic", "verification_hint": "Conferma che lo stub sia realmente raggiungibile dal call graph o dal diff corrente", "promotion_gate": "strict_verified"]
        )
    }

    private static func patternBugAudit(
        scopeFiles: [String],
        workspacePath: URL,
        patterns: [(needle: String, severity: FindingSeverity, message: String, remediation: String, confidence: Double)],
        sourceTool: String,
        summaryWhenEmpty: String,
        summaryWhenNonEmpty: String
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        var findings: [CodeReviewFinding] = []
        for file in scopeFiles {
            guard !isAuditSourceFile(file),
                  let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }
            for (index, line) in lines.enumerated() {
                let lower = line.lowercased()
                for pattern in patterns where lower.contains(pattern.needle.lowercased()) {
                    findings.append(
                        makeFinding(
                            severity: pattern.severity,
                            category: .correctness,
                            origin: .bugHunter,
                            filePath: file,
                            lineNumber: index + 1,
                            message: pattern.message,
                            suggestedFix: pattern.remediation,
                            confidence: pattern.confidence,
                            evidence: line.trimmingCharacters(in: .whitespacesAndNewlines),
                            sourceTool: sourceTool,
                            blocking: pattern.severity == .critical
                        )
                    )
                }
            }
        }
        return (
            deduplicate(findings),
            !scopeFiles.isEmpty,
            findings.isEmpty ? summaryWhenEmpty : summaryWhenNonEmpty,
            [],
            ["signal_type": "pattern", "verification_hint": "Conferma il path runtime e la raggiungibilità del codice segnalato", "promotion_gate": "strict_verified"]
        )
    }
}
