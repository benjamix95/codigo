import Foundation

// MARK: - AgentNameAssigner

/// Assegna nomi univoci agli agenti secondo la convenzione §6.13:
/// `{task_label}-{role}` con indice se multipli dello stesso ruolo.
///
/// L'Orchestrator è l'unico autorizzato ad assegnare nomi (§5.12 inv. 9).
public actor AgentNameAssigner {

    /// Contatore per ruolo per task, per gestire agent-1, agent-2, ecc.
    private var counters: [String: [AgentRole: Int]] = [:]

    /// Set di nomi già assegnati nel job corrente.
    private var assignedNames: Set<String> = []

    public init() {}

    // MARK: - Assign

    /// Assegna un nome agente per il task e il ruolo specificati.
    ///
    /// Formato: `{taskLabel}-{role}` oppure `{taskLabel}-{role}-{n}`
    /// se il ruolo è già stato usato per questo task.
    ///
    /// - Parameters:
    ///   - task: il TaskNode (usa `taskLabel` o lo deriva dal `title`)
    ///   - role: il ruolo dell'agente
    /// - Returns: nome agente univoco nel job
    public func assign(task: TaskNode, role: AgentRole) -> String {
        let label = resolveTaskLabel(task)
        let key = task.taskId

        if counters[key] == nil {
            counters[key] = [:]
        }

        let count = (counters[key]?[role] ?? 0) + 1
        counters[key]?[role] = count

        let baseName = "\(label)-\(role.rawValue)"
        let name = count > 1 ? "\(baseName)-\(count)" : baseName

        assignedNames.insert(name)
        return name
    }

    // MARK: - Query

    /// Restituisce tutti i nomi assegnati finora.
    public var allAssignedNames: Set<String> {
        assignedNames
    }

    /// Verifica se un nome è già in uso.
    public func isAssigned(_ name: String) -> Bool {
        assignedNames.contains(name)
    }

    /// Quanti agenti di un dato ruolo sono stati assegnati per un task.
    public func countForRole(_ role: AgentRole, taskId: String) -> Int {
        counters[taskId]?[role] ?? 0
    }

    // MARK: - Reset

    public func reset() {
        counters.removeAll()
        assignedNames.removeAll()
    }

    // MARK: - Private

    /// Risolve il task_label: usa `taskLabel` se presente,
    /// altrimenti lo genera dal `title` (§6.13 — max 30 char, PascalCase).
    private func resolveTaskLabel(_ task: TaskNode) -> String {
        if let label = task.taskLabel, !label.isEmpty {
            return label
        }
        return Self.deriveLabel(from: task.title)
    }

    /// Genera un label PascalCase dal titolo (max 30 char).
    static func deriveLabel(from title: String) -> String {
        let words = title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let joined = words.joined()
        return String(joined.prefix(30))
    }
}
