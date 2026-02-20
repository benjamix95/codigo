import SwiftUI

struct AgentSwarmHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("swarm_help_lang") private var helpLang = "en"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.swarmColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "ant.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.swarmColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent Swarm")
                        .font(.system(size: 15, weight: .bold))
                    Text(
                        helpLang == "it"
                            ? "Guida al sistema multi-agente" : "Multi-agent system guide"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("", selection: $helpLang) {
                    Text("EN").tag("en")
                    Text("IT").tag("it")
                }
                .pickerStyle(.segmented)
                .frame(width: 90)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().opacity(0.4)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if helpLang == "en" { englishContent } else { italianContent }
                }
                .padding(20)
            }
        }
        .frame(width: 620, height: 560)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - English

    private var englishContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpSection(
                icon: "questionmark.circle.fill",
                color: DesignSystem.Colors.info,
                title: "What is Agent Swarm?"
            ) {
                Text(
                    "Agent Swarm is a multi-agent orchestration system that coordinates seven specialized AI agents to solve complex coding tasks. An orchestrator analyzes your request, creates a structured plan, and delegates tasks to expert agents that run in sequence or in parallel."
                )
                .helpBody()
            }

            helpSection(
                icon: "gearshape.2.fill",
                color: DesignSystem.Colors.swarmColor,
                title: "How It Works"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    stepRow(number: 1, text: "You send a message in Agent Swarm mode.")
                    stepRow(
                        number: 2,
                        text:
                            "The orchestrator analyzes your request and workspace context, then produces a JSON plan with ordered tasks assigned to roles."
                    )
                    stepRow(
                        number: 3,
                        text:
                            "Workers execute tasks sequentially (or in parallel when they share the same order). Each worker is a CLI instance with a specialized system prompt."
                    )
                    stepRow(
                        number: 4,
                        text:
                            "The chat streams combined output with headers showing which agent produced each block."
                    )
                }
            }

            helpSection(
                icon: "person.3.fill",
                color: .purple,
                title: "The Seven Specialist Roles"
            ) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    roleCard(
                        icon: "map.fill", name: "Planner",
                        desc: "Breaks down tasks into clear steps", color: .blue)
                    roleCard(
                        icon: "chevron.left.forwardslash.chevron.right", name: "Coder",
                        desc: "Implements code changes", color: .green)
                    roleCard(
                        icon: "ladybug.fill", name: "Debugger", desc: "Finds and fixes bugs",
                        color: .orange)
                    roleCard(
                        icon: "eye.fill", name: "Reviewer", desc: "Reviews code quality",
                        color: .cyan)
                    roleCard(
                        icon: "doc.text.fill", name: "Doc Writer", desc: "Writes documentation",
                        color: .indigo)
                    roleCard(
                        icon: "lock.shield.fill", name: "Security Auditor",
                        desc: "Analyzes vulnerabilities", color: .red)
                    roleCard(
                        icon: "checkmark.diamond.fill", name: "Test Writer",
                        desc: "Writes unit & integration tests", color: .mint)
                }
            }

            helpSection(
                icon: "cpu",
                color: .orange,
                title: "Supported Backends"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "Both the **orchestrator** (planning) and **workers** (execution) can use different backends:"
                    )
                    .helpBody()

                    backendRow(
                        name: "Codex CLI",
                        desc: "OpenAI Codex — fast, reliable. Default worker backend.",
                        icon: "terminal.fill",
                        color: DesignSystem.Colors.agentColor
                    )
                    backendRow(
                        name: "Claude Code CLI",
                        desc: "Anthropic Claude — excellent for complex reasoning and code review.",
                        icon: "brain.head.profile",
                        color: .purple
                    )
                    backendRow(
                        name: "Gemini CLI",
                        desc: "Google Gemini — large context window, great for analysis tasks.",
                        icon: "sparkles",
                        color: .blue
                    )
                    backendRow(
                        name: "OpenAI API",
                        desc: "Direct API calls for orchestration (gpt-4o-mini). Requires API key.",
                        icon: "cloud.fill",
                        color: .gray
                    )
                }
            }

            helpSection(
                icon: "slider.horizontal.3",
                color: .green,
                title: "Per-Role Backend Overrides"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "You can assign a different CLI backend to each specialist role. For example:"
                    )
                    .helpBody()
                    overrideExample("Coder → Claude Code", "Best for complex implementations")
                    overrideExample(
                        "Reviewer → Gemini CLI", "Large context for full codebase review")
                    overrideExample("TestWriter → Codex", "Fast test generation")
                    Text(
                        "Configure per-role overrides in **Settings → Agent Swarm → Worker Overrides**."
                    )
                    .helpBody()
                    .padding(.top, 4)
                }
            }

            helpSection(
                icon: "wrench.and.screwdriver.fill",
                color: .secondary,
                title: "Configuration"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    configRow(
                        key: "Orchestrator",
                        value:
                            "Select in the controls bar when in Swarm mode (OpenAI / Codex / Claude / Gemini)"
                    )
                    configRow(key: "Worker", value: "Default worker backend for all roles")
                    configRow(key: "Per-role overrides", value: "Settings → Agent Swarm tab")
                    configRow(
                        key: "Auto pipeline",
                        value: "Automatically appends Reviewer + TestWriter after Coder")
                    configRow(key: "Review loops", value: "Number of review → fix cycles (0–5)")
                    configRow(key: "Test retries", value: "Debugger attempts if tests fail")
                }
            }
        }
    }

    // MARK: - Italian

    private var italianContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpSection(
                icon: "questionmark.circle.fill",
                color: DesignSystem.Colors.info,
                title: "Cos'è Agent Swarm?"
            ) {
                Text(
                    "Agent Swarm è un sistema di orchestrazione multi-agente che coordina sette agenti AI specializzati per risolvere task complessi. Un orchestratore analizza la richiesta, crea un piano strutturato e delega i task ad agenti esperti che lavorano in sequenza o in parallelo."
                )
                .helpBody()
            }

            helpSection(
                icon: "gearshape.2.fill",
                color: DesignSystem.Colors.swarmColor,
                title: "Come Funziona"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    stepRow(number: 1, text: "Invii un messaggio in modalità Agent Swarm.")
                    stepRow(
                        number: 2,
                        text:
                            "L'orchestratore analizza la richiesta e il contesto del workspace, poi produce un piano JSON con task ordinati e assegnati a ruoli."
                    )
                    stepRow(
                        number: 3,
                        text:
                            "I worker eseguono i task in sequenza (o in parallelo se hanno lo stesso ordine). Ogni worker è un'istanza CLI con un prompt specializzato."
                    )
                    stepRow(
                        number: 4,
                        text:
                            "La chat mostra l'output combinato con intestazioni che indicano quale agente ha prodotto ciascun blocco."
                    )
                }
            }

            helpSection(
                icon: "person.3.fill",
                color: .purple,
                title: "I Sette Ruoli Specializzati"
            ) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    roleCard(
                        icon: "map.fill", name: "Planner", desc: "Scompone il task in passi chiari",
                        color: .blue)
                    roleCard(
                        icon: "chevron.left.forwardslash.chevron.right", name: "Coder",
                        desc: "Implementa le modifiche al codice", color: .green)
                    roleCard(
                        icon: "ladybug.fill", name: "Debugger", desc: "Trova e corregge bug",
                        color: .orange)
                    roleCard(
                        icon: "eye.fill", name: "Reviewer", desc: "Revisiona la qualità del codice",
                        color: .cyan)
                    roleCard(
                        icon: "doc.text.fill", name: "Doc Writer", desc: "Scrive documentazione",
                        color: .indigo)
                    roleCard(
                        icon: "lock.shield.fill", name: "Security Auditor",
                        desc: "Analizza vulnerabilità", color: .red)
                    roleCard(
                        icon: "checkmark.diamond.fill", name: "Test Writer",
                        desc: "Scrive test unitari e di integrazione", color: .mint)
                }
            }

            helpSection(
                icon: "cpu",
                color: .orange,
                title: "Backend Supportati"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "Sia l'**orchestratore** (pianificazione) che i **worker** (esecuzione) possono usare backend diversi:"
                    )
                    .helpBody()

                    backendRow(
                        name: "Codex CLI",
                        desc: "OpenAI Codex — veloce e affidabile. Worker predefinito.",
                        icon: "terminal.fill",
                        color: DesignSystem.Colors.agentColor
                    )
                    backendRow(
                        name: "Claude Code CLI",
                        desc:
                            "Anthropic Claude — eccellente per ragionamento complesso e code review.",
                        icon: "brain.head.profile",
                        color: .purple
                    )
                    backendRow(
                        name: "Gemini CLI",
                        desc: "Google Gemini — finestra di contesto ampia, ottimo per analisi.",
                        icon: "sparkles",
                        color: .blue
                    )
                    backendRow(
                        name: "OpenAI API",
                        desc:
                            "Chiamate API dirette per l'orchestrazione (gpt-4o-mini). Richiede API key.",
                        icon: "cloud.fill",
                        color: .gray
                    )
                }
            }

            helpSection(
                icon: "slider.horizontal.3",
                color: .green,
                title: "Override Backend Per-Ruolo"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "Puoi assegnare un backend CLI diverso a ogni ruolo specializzato. Esempio:"
                    )
                    .helpBody()
                    overrideExample("Coder → Claude Code", "Migliore per implementazioni complesse")
                    overrideExample(
                        "Reviewer → Gemini CLI", "Contesto ampio per review dell'intero codebase")
                    overrideExample("TestWriter → Codex", "Generazione test veloce")
                    Text(
                        "Configura gli override in **Impostazioni → Agent Swarm → Worker Overrides**."
                    )
                    .helpBody()
                    .padding(.top, 4)
                }
            }

            helpSection(
                icon: "wrench.and.screwdriver.fill",
                color: .secondary,
                title: "Configurazione"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    configRow(
                        key: "Orchestratore",
                        value:
                            "Seleziona nella barra controlli in modalità Swarm (OpenAI / Codex / Claude / Gemini)"
                    )
                    configRow(key: "Worker", value: "Backend worker predefinito per tutti i ruoli")
                    configRow(key: "Override per-ruolo", value: "Impostazioni → tab Agent Swarm")
                    configRow(
                        key: "Auto pipeline",
                        value: "Aggiunge automaticamente Reviewer + TestWriter dopo Coder")
                    configRow(key: "Loop di review", value: "Cicli review → fix (0–5)")
                    configRow(
                        key: "Retry test", value: "Tentativi del Debugger se i test falliscono")
                }
            }
        }
    }

    // MARK: - Reusable Components

    private func helpSection<Content: View>(
        icon: String,
        color: Color,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 20, height: 20)
                    .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))

                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }

            content()
                .padding(.leading, 28)
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(DesignSystem.Colors.swarmColor.opacity(0.7), in: Circle())

            Text(text)
                .helpBody()
        }
    }

    private func roleCard(icon: String, name: String, desc: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func backendRow(name: String, desc: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func overrideExample(_ config: String, _ reason: String) -> some View {
        HStack(spacing: 6) {
            Text("•")
                .foregroundStyle(.tertiary)
            Text(config)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.swarmColor)
            Text("— \(reason)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func configRow(key: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 110, alignment: .trailing)
                .foregroundStyle(.primary)

            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Text Style Extension

extension Text {
    fileprivate func helpBody() -> some View {
        self
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
}
