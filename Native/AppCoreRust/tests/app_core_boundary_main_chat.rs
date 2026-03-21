use app_core_protocol::app_core::{AppCoreRequest, AppCoreResponse, BoundaryAuditRequest};
use app_core_rust::dispatch;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn boundary_audit_enforces_broad_main_chat_prefix_for_nested_chat_legacy_files() {
    let workspace = make_workspace("broad-main-chat");
    write_file(
        &workspace,
        "Config/validation/rust-cutover-swift-allowlist.txt",
        concat!(
            "ui_view|App/SoloCodeApp/Sources/**/Views/**|SwiftUI/AppKit views are allowed during the Rust cutover.\n",
            "binding_adapter|App/SoloCodeApp/Sources/Chat/Support/PipelineRuntime/**|Pipeline runtime projection stays in Swift as UI/runtime glue outside Rust domain ownership.\n",
        ),
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Chat/Support/PipelineRuntime/PipelineIntegrationService.swift",
        "import Foundation\nfinal class PipelineIntegrationService {}\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Chat/Support/StoreRuntime/ChatStoreStreaming.swift",
        "import Foundation\nstruct ChatStoreStreaming {}\n",
    );

    let response = dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
        workspace_root: workspace.to_string_lossy().to_string(),
        allowlist_path: workspace.join("Config/validation/rust-cutover-swift-allowlist.txt").to_string_lossy().to_string(),
        candidate_files: vec!["App/SoloCodeApp/Sources/Chat/Support/PipelineRuntime/PipelineIntegrationService.swift".to_string()],
        new_files: vec![],
        enforce_legacy_zero_prefixes: vec!["App/SoloCodeApp/Sources/Chat".to_string()],
        legacy_non_ui_budget_by_prefix: Default::default(),
        include_missing_candidate_files: false,
    }))
    .expect("boundary dispatch should succeed");

    let AppCoreResponse::BoundaryAudit(report) = response;
    assert_eq!(report.summary.allowed_swift_files, 1);
    assert_eq!(report.summary.legacy_non_ui_files, 1);
    assert_eq!(report.summary.enforced_legacy_non_ui_files, 1);
    assert_eq!(report.enforced_prefix_counts.get("App/SoloCodeApp/Sources/Chat"), Some(&1));
}

#[test]
fn boundary_audit_treats_runtime_bridge_file_as_allowed_when_rule_is_present() {
    let workspace = make_workspace("runtime-bridge-allowlist");
    write_file(
        &workspace,
        "Config/validation/rust-cutover-swift-allowlist.txt",
        "binding_adapter|App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift|ConversationFlowCoordinator support is now a Swift bridge adapter over the Rust-owned direct-stream runtime.\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift",
        "import Foundation\nstruct RuntimeBridge {}\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift",
        "import Foundation\nstruct RuntimeLegacy {}\n",
    );

    let response = dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
        workspace_root: workspace.to_string_lossy().to_string(),
        allowlist_path: workspace.join("Config/validation/rust-cutover-swift-allowlist.txt").to_string_lossy().to_string(),
        candidate_files: vec!["App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift".to_string()],
        new_files: vec![],
        enforce_legacy_zero_prefixes: vec!["App/SoloCodeApp/Sources/Runtime".to_string()],
        legacy_non_ui_budget_by_prefix: Default::default(),
        include_missing_candidate_files: false,
    }))
    .expect("boundary dispatch should succeed");

    let AppCoreResponse::BoundaryAudit(report) = response;
    assert_eq!(report.summary.allowed_swift_files, 1);
    assert_eq!(report.summary.legacy_non_ui_files, 1);
    assert_eq!(report.summary.enforced_legacy_non_ui_files, 1);
    assert_eq!(report.enforced_prefix_counts.get("App/SoloCodeApp/Sources/Runtime"), Some(&1));
}

#[test]
fn boundary_audit_treats_runtime_direct_stream_adapter_file_as_allowed_when_rule_is_present() {
    let workspace = make_workspace("runtime-direct-stream-adapter");
    write_file(
        &workspace,
        "Config/validation/rust-cutover-swift-allowlist.txt",
        "binding_adapter|App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift|WorkspaceStore direct-stream loop is now a Swift adapter over Rust-owned provider event reduction and fail-closed runtime semantics.\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift",
        "import Foundation\nstruct RuntimeAdapter {}\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Runtime/NetworkMonitor.swift",
        "import Foundation\nstruct RuntimeLegacy {}\n",
    );

    let response = dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
        workspace_root: workspace.to_string_lossy().to_string(),
        allowlist_path: workspace.join("Config/validation/rust-cutover-swift-allowlist.txt").to_string_lossy().to_string(),
        candidate_files: vec!["App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift".to_string()],
        new_files: vec![],
        enforce_legacy_zero_prefixes: vec!["App/SoloCodeApp/Sources/Runtime".to_string()],
        legacy_non_ui_budget_by_prefix: Default::default(),
        include_missing_candidate_files: false,
    }))
    .expect("boundary dispatch should succeed");

    let AppCoreResponse::BoundaryAudit(report) = response;
    assert_eq!(report.summary.allowed_swift_files, 1);
    assert_eq!(report.summary.legacy_non_ui_files, 1);
    assert_eq!(report.summary.enforced_legacy_non_ui_files, 1);
    assert_eq!(report.enforced_prefix_counts.get("App/SoloCodeApp/Sources/Runtime"), Some(&1));
}

#[test]
fn boundary_audit_treats_storerust_bridge_files_as_allowed_when_rule_is_present() {
    let workspace = make_workspace("storerust-allowlist");
    write_file(
        &workspace,
        "Config/validation/rust-cutover-swift-allowlist.txt",
        "binding_adapter|App/SoloCodeApp/Sources/Chat/Support/StoreRust/**|StoreRust bridge files remain Swift adapter glue over Rust-owned main-chat store reducers.\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift",
        "import Foundation\nextension ChatStore {}\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Chat/Support/StoreRuntime/ChatStoreStreaming.swift",
        "import Foundation\nstruct ChatStoreStreaming {}\n",
    );

    let response = dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
        workspace_root: workspace.to_string_lossy().to_string(),
        allowlist_path: workspace.join("Config/validation/rust-cutover-swift-allowlist.txt").to_string_lossy().to_string(),
        candidate_files: vec!["App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift".to_string()],
        new_files: vec![],
        enforce_legacy_zero_prefixes: vec!["App/SoloCodeApp/Sources/Chat".to_string()],
        legacy_non_ui_budget_by_prefix: Default::default(),
        include_missing_candidate_files: false,
    }))
    .expect("boundary dispatch should succeed");

    let AppCoreResponse::BoundaryAudit(report) = response;
    assert_eq!(report.summary.allowed_swift_files, 1);
    assert_eq!(report.summary.legacy_non_ui_files, 1);
    assert_eq!(report.summary.enforced_legacy_non_ui_files, 1);
    assert_eq!(report.enforced_prefix_counts.get("App/SoloCodeApp/Sources/Chat"), Some(&1));
}

#[test]
fn boundary_audit_treats_plan_services_support_files_as_allowed_when_rules_are_present() {
    let workspace = make_workspace("plan-services-allowlist");
    write_file(
        &workspace,
        "Config/validation/rust-cutover-swift-allowlist.txt",
        concat!(
            "binding_adapter|App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanFlowHelpers.swift|Plan flow helper file now contains only panel-routing, epoch bookkeeping and UI-local policy glue over Rust-owned planning decisions.\n",
            "binding_adapter|App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanQuestionnaire.swift|Plan questionnaire helper file is retained only for UI-side clarification formatting, resume prompt helpers and generic task-reset glue outside the Rust-owned runtime path.\n",
            "binding_adapter|App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift|Chat thread core helpers remain Swift-side binding glue after removing plan-state classification from the runtime path.\n",
        ),
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanFlowHelpers.swift",
        "import Foundation\nstruct PlanFlowHelpers {}\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanQuestionnaire.swift",
        "import Foundation\nstruct PlanQuestionnaireHelpers {}\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift",
        "import Foundation\nstruct ChatThreadCoreHelpers {}\n",
    );

    let response = dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
        workspace_root: workspace.to_string_lossy().to_string(),
        allowlist_path: workspace.join("Config/validation/rust-cutover-swift-allowlist.txt").to_string_lossy().to_string(),
        candidate_files: vec![
            "App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanFlowHelpers.swift".to_string(),
            "App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanQuestionnaire.swift".to_string(),
            "App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift".to_string(),
        ],
        new_files: vec![],
        enforce_legacy_zero_prefixes: vec!["App/SoloCodeApp/Sources/Services".to_string()],
        legacy_non_ui_budget_by_prefix: Default::default(),
        include_missing_candidate_files: false,
    }))
    .expect("boundary dispatch should succeed");

    let AppCoreResponse::BoundaryAudit(report) = response;
    assert_eq!(report.summary.allowed_swift_files, 3);
    assert_eq!(report.summary.legacy_non_ui_files, 0);
    assert_eq!(report.summary.enforced_legacy_non_ui_files, 0);
    assert_eq!(report.enforced_prefix_counts.get("App/SoloCodeApp/Sources/Services"), None);
}


fn make_workspace(label: &str) -> PathBuf {
    let suffix = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
    let path = std::env::temp_dir().join(format!("solocode-app-core-rust-{label}-{suffix}"));
    fs::create_dir_all(&path).expect("workspace dir");
    path
}

fn write_file(root: &PathBuf, relative: &str, contents: &str) {
    let path = root.join(relative);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("parent dir");
    }
    fs::write(path, contents).expect("write file");
}
