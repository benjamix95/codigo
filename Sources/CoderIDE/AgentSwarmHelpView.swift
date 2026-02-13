import SwiftUI

struct AgentSwarmHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("swarm_help_lang") private var helpLang = "en"  // "en" | "it"

    var body: some View {
        VStack(spacing: 0) {
            // Header with lang toggle
            HStack {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "ant.fill")
                        .font(.title2)
                        .foregroundStyle(DesignSystem.Colors.swarmColor)
                    Text(helpLang == "it" ? "Agent Swarm – Guida" : "Agent Swarm – Guide")
                        .font(DesignSystem.Typography.title2)
                }
                Spacer()
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Button {
                        helpLang = "en"
                    } label: {
                        Text("EN")
                            .font(DesignSystem.Typography.captionMedium)
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .background(helpLang == "en" ? DesignSystem.Colors.swarmColor.opacity(0.3) : Color.clear)
                            .cornerRadius(DesignSystem.CornerRadius.small)
                    }
                    .buttonStyle(.plain)
                    Button {
                        helpLang = "it"
                    } label: {
                        Text("IT")
                            .font(DesignSystem.Typography.captionMedium)
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .background(helpLang == "it" ? DesignSystem.Colors.swarmColor.opacity(0.3) : Color.clear)
                            .cornerRadius(DesignSystem.CornerRadius.small)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(DesignSystem.Spacing.md)
            .overlay {
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(DesignSystem.Colors.divider)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    if helpLang == "en" {
                        englishContent
                    } else {
                        italianContent
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }
        }
        .frame(width: 580, height: 520)
    }

    // MARK: - English
    private var englishContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Group {
                sectionTitle("What is Agent Swarm?")
                Text("Agent Swarm is a multi-agent system that coordinates seven specialized AI agents to solve complex coding tasks. Instead of a single agent handling everything, an orchestrator analyzes your request, creates a structured plan, and delegates specific tasks to expert agents (Planner, Coder, Debugger, Reviewer, DocWriter, SecurityAuditor, TestWriter).")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                sectionTitle("How It Works")
                Text("1. You send a message in Agent Swarm mode.\n2. The orchestrator (OpenAI or Codex) analyzes your request and workspace context, then produces a JSON plan: an ordered list of tasks, each assigned to a role.\n3. Workers execute the tasks sequentially. Each worker is a Codex instance with a specialized system prompt (e.g. Planner, Coder). Workers receive the accumulated output of previous agents for context.\n4. The chat streams the combined output, with headers like ## Planner, ## Coder to show which agent produced each block.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                sectionTitle("The Seven Specialist Roles")
                roleRow("Planner", "Breaks down the task into clear steps. Produces a structured plan without writing code.")
                roleRow("Coder", "Implements code changes according to the plan. Uses tools (edit files, run commands, MCP).")
                roleRow("Debugger", "Identifies bugs, analyzes stack traces, and fixes issues.")
                roleRow("Reviewer", "Reviews code for style, best practices, and suggests optimizations.")
                roleRow("DocWriter", "Writes documentation: README, comments, docstrings.")
                roleRow("SecurityAuditor", "Analyzes code for vulnerabilities, insecure dependencies, and data exposure.")
                roleRow("TestWriter", "Writes unit and integration tests.")

                sectionTitle("Orchestrator Backend")
                Text("The orchestrator decides which agents to run and in what order. You can choose:\n• **OpenAI** (default): Uses gpt-4o-mini for fast, lightweight planning. Requires an OpenAI API key.\n• **Codex**: Uses Codex for planning. No extra API key, but slower and more token-heavy.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                sectionTitle("Workers (Always Codex)")
                Text("All specialists run as Codex CLI processes. They inherit your Codex configuration: model, MCP servers, skills, sandbox mode. Each worker gets a role-specific prompt plus the previous agents’ output.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                sectionTitle("Example Flow")
                Text("Request: \"Add input validation to the login form\"\n\n1. Orchestrator outputs: [{role:\"planner\", taskDescription:\"Analyze login form...\", order:1}, {role:\"coder\", ...}, {role:\"reviewer\", ...}]\n2. Planner runs first → outputs a detailed plan.\n3. Coder receives plan + workspace → implements changes.\n4. Reviewer receives plan + modified code → suggests improvements.\n\nYou see the full stream in chat with ## Planner, ## Coder, ## Reviewer sections.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                sectionTitle("Configuration")
                Text("• **Chat**: Select Orchestrator (OpenAI / Codex) under the input when in Agent Swarm mode.\n• **Settings**: Agent Swarm tab to change the orchestrator backend.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
        }
    }

    // MARK: - Italian
    private var italianContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Group {
                sectionTitle("Cos’è Agent Swarm?")
                Text("Agent Swarm è un sistema multi-agente che coordina sette agenti AI specializzati per risolvere compiti di programmazione complessi. Invece di un singolo agente che fa tutto, un orchestratore analizza la richiesta, crea un piano strutturato e assegna task specifici ad agenti esperti (Planner, Coder, Debugger, Reviewer, DocWriter, SecurityAuditor, TestWriter).")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                sectionTitle("Come funziona")
                Text("1. Invii un messaggio in modalità Agent Swarm.\n2. L’orchestratore (OpenAI o Codex) analizza la richiesta e il contesto del workspace, poi produce un piano JSON: una lista ordinata di task, ciascuno assegnato a un ruolo.\n3. I worker eseguono i task in sequenza. Ogni worker è un’istanza Codex con un system prompt specializzato (es. Planner, Coder). I worker ricevono l’output cumulativo degli agenti precedenti come contesto.\n4. La chat streama l’output combinato, con intestazioni ## Planner, ## Coder per indicare quale agente ha prodotto ogni blocco.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                sectionTitle("I sette ruoli specializzati")
                roleRow("Planner", "Scompone il compito in passi chiari. Produce un piano strutturato senza scrivere codice.")
                roleRow("Coder", "Implementa le modifiche al codice secondo il piano. Usa strumenti (edit file, comandi, MCP).")
                roleRow("Debugger", "Identifica bug, analizza stack trace e risolve problemi.")
                roleRow("Reviewer", "Revisiona il codice per stile, best practice e suggerisce ottimizzazioni.")
                roleRow("DocWriter", "Scrive documentazione: README, commenti, docstring.")
                roleRow("SecurityAuditor", "Analizza il codice per vulnerabilità, dipendenze insicure ed esposizione dati.")
                roleRow("TestWriter", "Scrive test unitari e di integrazione.")

                sectionTitle("Backend dell’orchestratore")
                Text("L’orchestratore decide quali agenti eseguire e in che ordine. Puoi scegliere:\n• **OpenAI** (default): Usa gpt-4o-mini per pianificazione veloce e leggera. Richiede API key OpenAI.\n• **Codex**: Usa Codex per la pianificazione. Nessuna API key aggiuntiva, ma più lento e costoso in token.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                sectionTitle("Worker (sempre Codex)")
                Text("Tutti gli specialisti girano come processi Codex CLI. Ereditano la tua config Codex: modello, server MCP, skill, modalità sandbox. Ogni worker riceve un prompt specifico per il ruolo più l’output degli agenti precedenti.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                sectionTitle("Esempio di flusso")
                Text("Richiesta: \"Aggiungi validazione degli input al form di login\"\n\n1. L’orchestratore produce: [{role:\"planner\", taskDescription:\"Analizza il form di login...\", order:1}, {role:\"coder\", ...}, {role:\"reviewer\", ...}]\n2. Il Planner parte per primo → produce un piano dettagliato.\n3. Il Coder riceve piano + workspace → implementa le modifiche.\n4. Il Reviewer riceve piano + codice modificato → suggerisce miglioramenti.\n\nVedi tutto in streaming nella chat con le sezioni ## Planner, ## Coder, ## Reviewer.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                sectionTitle("Configurazione")
                Text("• **Chat**: Seleziona Orchestrator (OpenAI / Codex) sotto il campo input quando sei in modalità Agent Swarm.\n• **Impostazioni**: Tab Agent Swarm per cambiare il backend dell’orchestratore.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(DesignSystem.Colors.swarmColor)
    }

    private func roleRow(_ role: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("**\(role)**")
                .font(DesignSystem.Typography.subheadlineMedium)
            Text(desc)
                .font(DesignSystem.Typography.caption)
        }
        .foregroundStyle(DesignSystem.Colors.textPrimary)
    }
}
