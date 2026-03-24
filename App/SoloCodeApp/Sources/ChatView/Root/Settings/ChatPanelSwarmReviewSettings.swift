import Foundation
import SwiftUI

// MARK: - ChatPanelSwarmReviewSettings

/// Groups all swarm + code-review @AppStorage into a `DynamicProperty`.
/// Keeps ChatPanelView lean and improves readability.
struct ChatPanelSwarmReviewSettings: DynamicProperty {

    // MARK: - Swarm

    @AppStorage("swarm_orchestrator") var swarmOrchestrator = "auto"
    @AppStorage("swarm_worker_backend") var swarmWorkerBackend = "auto"
    @AppStorage("swarm_provider_auto_migrated_v1") var swarmProviderAutoMigrated = false
    @AppStorage("swarm_enabled_roles") var swarmEnabledRoles =
        "explorer,coder,debugger,reviewer,testWriter"

    // MARK: - Code Review

    @AppStorage("code_review_partitions") var codeReviewPartitions = 3
    @AppStorage("code_review_analysis_only") var codeReviewAnalysisOnly = false
    @AppStorage("code_review_max_rounds") var codeReviewMaxRounds = 3
    @AppStorage("code_review_analysis_backend") var codeReviewAnalysisBackend = "auto"
    @AppStorage("code_review_execution_backend") var codeReviewExecutionBackend = "auto"
    @AppStorage("code_review_quick_commands_custom_json")
    var codeReviewQuickCommandsCustomJSON = ""
}
