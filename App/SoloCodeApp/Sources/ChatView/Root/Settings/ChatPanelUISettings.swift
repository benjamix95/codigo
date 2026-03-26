import Foundation
import SwiftUI

// MARK: - ChatPanelUISettings

/// Groups behaviour, layout, and miscellaneous @AppStorage into a
/// `DynamicProperty`.  Panel-width changes, behaviour toggles, and
/// web-search / summarisation settings live here.
struct ChatPanelUISettings: DynamicProperty {

    // MARK: - Behavior

    @AppStorage("global_yolo") var globalYolo = false
    @AppStorage("task_panel_enabled") var taskPanelEnabled = false
    @AppStorage("plan_mode_backend") var planModeBackend = "codex"
    /// When true, plan build pipeline tasks have no step-to-step dependencies (faster, higher conflict risk).
    @AppStorage("plan_build_parallel_steps_enabled") var planBuildParallelStepsEnabled = false
    @AppStorage("unified_tool_runtime_enabled") var unifiedToolRuntimeEnabled = true
    @AppStorage("agents_hard_block_enabled") var agentsHardBlockEnabled = true
    @AppStorage("mcp_edit_enforcement_enabled") var mcpEditEnforcementEnabled = true

    // MARK: - Web Search

    @AppStorage("web_search_provider") var webSearchProvider = "duckduckgo"
    @AppStorage("brave_search_api_key") var braveSearchApiKey = ""
    @AppStorage("tavily_api_key") var tavilyApiKey = ""
    @AppStorage("serper_api_key") var serperApiKey = ""

    // MARK: - Summarization

    @AppStorage("summarize_threshold") var summarizeThreshold = 0.8
    @AppStorage("summarize_keep_last") var summarizeKeepLast = 6
    @AppStorage("summarize_provider") var summarizeProvider = "openai-api"

    // MARK: - Context

    @AppStorage("context_scope_mode") var contextScopeModeRaw = "auto"

    // MARK: - Panel Layout

    @AppStorage("plan_panel_width") var planPanelWidthStorage: Double = 320
    @AppStorage("debug_panel_width") var debugPanelWidthStorage: Double = 340
    @AppStorage("swarm_panel_width") var swarmPanelWidthStorage: Double = 360
    @AppStorage("code_review_panel_width") var codeReviewPanelWidthStorage: Double = 380
    @AppStorage("git_panel_width") var gitPanelWidthStorage: Double = 380
    @AppStorage("auto_resize_side_panels") var autoResizeSidePanels = true
}
