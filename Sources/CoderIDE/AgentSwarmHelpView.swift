import SwiftUI

struct AgentSwarmHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("swarm_help_lang") private var helpLang = "en"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "ant.fill")
                        .font(.title3)
                        .foregroundStyle(.cyan)
                    Text(helpLang == "it" ? "Agent Swarm -- Guida" : "Agent Swarm -- Guide")
                        .font(.title3)
                }
                Spacer()

                Picker("", selection: $helpLang) {
                    Text("EN").tag("en")
                    Text("IT").tag("it")
                }
                .pickerStyle(.segmented)
                .frame(width: 100)

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if helpLang == "en" { englishContent }
                    else { italianContent }
                }
                .padding(16)
            }
        }
        .frame(width: 580, height: 520)
    }

    private var englishContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("What is Agent Swarm?")
            bodyText("Agent Swarm is a multi-agent system that coordinates seven specialized AI agents to solve complex coding tasks. Instead of a single agent handling everything, an orchestrator analyzes your request, creates a structured plan, and delegates specific tasks to expert agents (Planner, Coder, Debugger, Reviewer, DocWriter, SecurityAuditor, TestWriter).")

            sectionTitle("How It Works")
            bodyText("1. You send a message in Agent Swarm mode.\n2. The orchestrator (OpenAI or Codex) analyzes your request and workspace context, then produces a JSON plan: an ordered list of tasks, each assigned to a role.\n3. Workers execute the tasks sequentially. Each worker is a Codex instance with a specialized system prompt.\n4. The chat streams the combined output, with headers like ## Planner, ## Coder to show which agent produced each block.")

            sectionTitle("The Seven Specialist Roles")
            roleRow("Planner", "Breaks down the task into clear steps without writing code.")
            roleRow("Coder", "Implements code changes according to the plan.")
            roleRow("Debugger", "Identifies bugs, analyzes stack traces, and fixes issues.")
            roleRow("Reviewer", "Reviews code for style, best practices, and suggests optimizations.")
            roleRow("DocWriter", "Writes documentation: README, comments, docstrings.")
            roleRow("SecurityAuditor", "Analyzes code for vulnerabilities and insecure dependencies.")
            roleRow("TestWriter", "Writes unit and integration tests.")

            sectionTitle("Orchestrator Backend")
            bodyText("The orchestrator decides which agents to run and in what order. You can choose:\n- **OpenAI** (default): Uses gpt-4o-mini for fast, lightweight planning.\n- **Codex**: Uses Codex for planning. No extra API key, but slower.")

            sectionTitle("Workers (Always Codex)")
            bodyText("All specialists run as Codex CLI processes. They inherit your Codex configuration: model, MCP servers, skills, sandbox mode.")

            sectionTitle("Configuration")
            bodyText("- **Chat**: Select Orchestrator (OpenAI / Codex) under the input when in Agent Swarm mode.\n- **Settings**: Agent Swarm tab to change the orchestrator backend.")
        }
    }

    private var italianContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("What is Agent Swarm?")
            bodyText("Agent Swarm is a multi-agent system that coordinates seven specialized AI agents to solve complex tasks. An orchestrator analyzes the request, creates a structured plan and assigns tasks to expert agents (Planner, Coder, Debugger, Reviewer, DocWriter, SecurityAuditor, TestWriter).")

            sectionTitle("How It Works")
            bodyText("1. You send a message in Agent Swarm mode.\n2. The orchestrator (OpenAI or Codex) produces a JSON plan: an ordered list of tasks with assigned roles.\n3. Workers execute tasks sequentially as Codex instances with specialized prompts.\n4. The chat streams the combined output with headers per agent.")

            sectionTitle("The Seven Specialist Roles")
            roleRow("Planner", "Breaks down the task into clear steps without writing code.")
            roleRow("Coder", "Implements code changes according to the plan.")
            roleRow("Debugger", "Identifies bugs and resolves issues.")
            roleRow("Reviewer", "Reviews code for style and best practices.")
            roleRow("DocWriter", "Writes documentation: README, comments, docstrings.")
            roleRow("SecurityAuditor", "Analyzes for vulnerabilities and insecure dependencies.")
            roleRow("TestWriter", "Writes unit and integration tests.")

            sectionTitle("Orchestrator Backend")
            bodyText("The orchestrator decides which agents to run. You can choose:\n- **OpenAI** (default): Fast and lightweight.\n- **Codex**: No extra API key needed, but slower.")

            sectionTitle("Configuration")
            bodyText("- **Chat**: Select Orchestrator under the input field in Agent Swarm mode.\n- **Settings**: Agent Swarm tab to change backend.")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.cyan)
    }

    private func bodyText(_ text: String) -> some View {
        Text(.init(text))
            .font(.body)
    }

    private func roleRow(_ role: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(role).font(.subheadline.weight(.semibold))
            Text(desc).font(.caption).foregroundStyle(.secondary)
        }
    }
}
