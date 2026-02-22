import Foundation

enum PromptExecutionPolicy {
    static let completionContract = """
    Completion contract obbligatorio:
    - Dopo ogni ciclo tool, decidi esplicitamente: continue oppure finalize.
    - finalize è obbligatorio quando l'obiettivo è raggiunto oppure quando esiste un blocco reale non risolvibile.
    - In caso di blocco: indica causa, evidenza sintetica e prossimo passo concreto.
    - Vietato terminare con solo reasoning o aggiornamenti intermedi.
    - Se hai usato tool/comandi, la risposta finale deve includere: cosa hai fatto, cosa hai verificato, esito.
    """

    static let doNotStopEarly = """
    Disciplina di esecuzione:
    - Non fermarti a metà task.
    - Non lasciare output incompleto dopo tool call.
    - Se servono altri step, continua in autonomia fino al completamento o blocco dichiarato.
    """
}
