import Foundation

/// Eventi emessi durante lo streaming delle risposte LLM
public enum StreamEvent: Sendable {
    /// Inizio di un messaggio
    case started
    
    /// Delta di testo (token)
    case textDelta(String)
    
    /// Fine del messaggio
    case completed
    
    /// Errore durante lo streaming
    case error(String)
    
    /// Evento generico da provider CLI (es. Codex JSONL)
    case raw(type: String, payload: [String: String])
}
