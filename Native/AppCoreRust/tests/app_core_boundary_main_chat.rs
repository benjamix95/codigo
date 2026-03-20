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
        allowlist_path: workspace
            .join("Config/validation/rust-cutover-swift-allowlist.txt")
            .to_string_lossy()
            .to_string(),
        candidate_files: vec![
            "App/SoloCodeApp/Sources/Chat/Support/PipelineRuntime/PipelineIntegrationService.swift"
                .to_string(),
        ],
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
    assert_eq!(
        report.enforced_prefix_counts.get("App/SoloCodeApp/Sources/Chat"),
        Some(&1)
    );
}

#[test]
fn boundary_audit_enforces_broad_main_chat_prefix_for_nested_accounts_legacy_files() {
    let workspace = make_workspace("broad-main-chat-accounts");
    write_file(
        &workspace,
        "Config/validation/rust-cutover-swift-allowlist.txt",
        "binding_adapter|App/SoloCodeApp/Sources/Accounts/Support/**|Relocated account support adapters remain Swift-only support code outside main-chat ownership.\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Accounts/Support/CLIAccountRouter.swift",
        "import Foundation\nstruct CLIAccountRouter {}\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Accounts/Login/CLIAccountLoginCoordinator.swift",
        "import Foundation\nfinal class CLIAccountLoginCoordinator {}\n",
    );

    let response = dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
        workspace_root: workspace.to_string_lossy().to_string(),
        allowlist_path: workspace
            .join("Config/validation/rust-cutover-swift-allowlist.txt")
            .to_string_lossy()
            .to_string(),
        candidate_files: vec!["App/SoloCodeApp/Sources/Accounts/Support/CLIAccountRouter.swift".to_string()],
        new_files: vec![],
        enforce_legacy_zero_prefixes: vec!["App/SoloCodeApp/Sources/Accounts".to_string()],
        legacy_non_ui_budget_by_prefix: Default::default(),
        include_missing_candidate_files: false,
    }))
    .expect("boundary dispatch should succeed");

    let AppCoreResponse::BoundaryAudit(report) = response;
    assert_eq!(report.summary.allowed_swift_files, 1);
    assert_eq!(report.summary.legacy_non_ui_files, 1);
    assert_eq!(report.summary.enforced_legacy_non_ui_files, 1);
    assert_eq!(
        report.enforced_prefix_counts.get("App/SoloCodeApp/Sources/Accounts"),
        Some(&1)
    );
}

fn make_workspace(label: &str) -> PathBuf {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system time")
        .as_nanos();
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
