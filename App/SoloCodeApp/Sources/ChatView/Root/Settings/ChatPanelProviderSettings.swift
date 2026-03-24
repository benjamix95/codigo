import Foundation
import SwiftUI

// MARK: - ChatPanelProviderSettings

/// Groups all provider / model / API-key / CLI @AppStorage into a single
/// `DynamicProperty` struct.  SwiftUI still tracks each nested
/// `@AppStorage` individually, so only actual value changes trigger body
/// re-evaluation — but the declaration footprint drops from 24 loose
/// properties to one `var providerSettings`.
struct ChatPanelProviderSettings: DynamicProperty {

    // MARK: - Codex

    @AppStorage("codex_path") var codexPath = ""
    @AppStorage("codex_sandbox") var codexSandbox = ""
    @AppStorage("codex_session_full_access") var codexSessionFullAccess = false
    @AppStorage("codex_ask_for_approval") var codexAskForApproval = "never"
    @AppStorage("codex_model_override") var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort") var codexReasoningEffort = "low"
    @AppStorage("codex_model_provider") var codexModelProvider = ""
    @AppStorage("codex_prefer_responses_wire_api")
    var codexPreferResponsesWireAPI = false

    // MARK: - OpenAI

    @AppStorage("openai_api_key") var openaiApiKey = ""
    @AppStorage("openai_model") var openaiModel = "gpt-4o-mini"

    // MARK: - Anthropic

    @AppStorage("anthropic_api_key") var anthropicApiKey = ""
    @AppStorage("anthropic_model") var anthropicModel = "claude-sonnet-4-6"

    // MARK: - Google

    @AppStorage("google_api_key") var googleApiKey = ""
    @AppStorage("google_model") var googleModel = "gemini-2.5-pro"

    // MARK: - OpenRouter

    @AppStorage("openrouter_api_key") var openrouterApiKey = ""
    @AppStorage("openrouter_model") var openrouterModel = "anthropic/claude-sonnet-4-6"

    // MARK: - Claude CLI

    @AppStorage("claude_path") var claudePath = ""
    @AppStorage("claude_model") var claudeModel = "claude-sonnet-4-6"
    @AppStorage("claude_allowed_tools") var claudeAllowedTools =
        "Read,Edit,Bash,Write,Search,Task,TodoWrite,WebSearch,WebFetch"

    // MARK: - Gemini CLI

    @AppStorage("gemini_cli_path") var geminiCliPath = ""
    @AppStorage("gemini_model_override") var geminiModelOverride = ""

    // MARK: - Kilo

    @AppStorage("kilo_path") var kiloPath = ""
    @AppStorage("kilo_model") var kiloModel = ""

    // MARK: - Multi-CLI

    @AppStorage("multi_cli_account_enabled") var multiCLIAccountEnabled = false
}
