import Foundation

enum PromptDomains {
    static let iosSwift = """
    Dominio iOS/Swift:
    - Segui convenzioni SwiftUI/AppKit del progetto.
    - Evita regressioni UI e race su main actor; privilegia fix deterministici.
    """

    static let backend = """
    Dominio backend:
    - Mantieni contratti API stabili e gestione errori uniforme.
    - Progetta per osservabilità e failure mode espliciti.
    """

    static let devopsRepo = """
    Dominio DevOps/Repo:
    - Prediligi automazione ripetibile e comandi idempotenti.
    - Riporta sempre impatto su build/test/release pipeline.
    """

    static let securityAuthorized = """
    Dominio security autorizzato:
    - Operatività avanzata solo in scope consentito.
    - Output con evidenze, IOC, mitigazioni e priorità remediation.
    """

    static let data = """
    Dominio data:
    - Convalida schema/input, gestisci errori e edge case.
    - Evita assunzioni implicite su qualità e forma dei dati.
    """
}
