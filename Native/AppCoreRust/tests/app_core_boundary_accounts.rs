use app_core_protocol::app_core::{AppCoreRequest, AppCoreResponse, BoundaryAuditRequest};
use app_core_rust::dispatch;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn boundary_audit_enforces_broad_main_chat_prefix_for_nested_accounts_legacy_files() {
    let workspace = make_workspace("broad-main-chat-accounts");
    write_file(
        &workspace,
        "Config/validation/rust-cutover-swift-allowlist.txt",
        "binding_adapter|App/SoloCodeApp/Sources/Accounts/Support/**|Relocated account support adapters remain Swift-only support code outside main-chat ownership.\n",
    );
    write_file(&workspace, "App/SoloCodeApp/Sources/Accounts/Support/CLIAccountRouter.swift", "import Foundation\nstruct CLIAccountRouter {}\n");
    write_file(&workspace, "App/SoloCodeApp/Sources/Accounts/Login/CLIAccountLoginCoordinator.swift", "import Foundation\nfinal class CLIAccountLoginCoordinator {}\n");

    let response = dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
        workspace_root: workspace.to_string_lossy().to_string(),
        allowlist_path: workspace.join("Config/validation/rust-cutover-swift-allowlist.txt").to_string_lossy().to_string(),
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
    assert_eq!(report.enforced_prefix_counts.get("App/SoloCodeApp/Sources/Accounts"), Some(&1));
}

#[test]
fn boundary_audit_treats_account_models_as_allowed_when_rule_is_present() {
    assert_accounts_rule(
        "accounts-models-allowlist",
        "binding_adapter|App/SoloCodeApp/Sources/Accounts/CLIAccountModels.swift|CLI account models are Swift-side DTO glue over Rust-owned account routing and provider runtime domains.\n",
        "App/SoloCodeApp/Sources/Accounts/CLIAccountModels.swift",
        "import Foundation\nstruct CLIAccount {}\n",
    );
}

#[test]
fn boundary_audit_treats_account_secrets_store_as_allowed_when_rule_is_present() {
    assert_accounts_rule(
        "accounts-secrets-allowlist",
        "binding_adapter|App/SoloCodeApp/Sources/Accounts/CLIAccountSecretsStore.swift|CLI account secrets store is a macOS Keychain wrapper and remains platform glue outside Rust business logic.\n",
        "App/SoloCodeApp/Sources/Accounts/CLIAccountSecretsStore.swift",
        "import Foundation\nfinal class CLIAccountSecretsStore {}\n",
    );
}

#[test]
fn boundary_audit_treats_account_usage_ledger_as_allowed_when_rule_is_present() {
    assert_accounts_rule(
        "accounts-ledger-allowlist",
        "binding_adapter|App/SoloCodeApp/Sources/Accounts/CLIAccountUsageLedgerStore.swift|CLI account usage ledger store is a local persistence adapter for raw usage events consumed by Rust-owned routing policy.\n",
        "App/SoloCodeApp/Sources/Accounts/CLIAccountUsageLedgerStore.swift",
        "import Foundation\nfinal class CLIAccountUsageLedgerStore {}\n",
    );
}

#[test]
fn boundary_audit_treats_account_login_sheet_as_ui_when_rule_is_present() {
    assert_accounts_rule(
        "accounts-login-sheet-ui",
        "ui_view|App/SoloCodeApp/Sources/Accounts/CLIAccountLoginSheet.swift|Account login sheet is a SwiftUI presentation shell.\n",
        "App/SoloCodeApp/Sources/Accounts/CLIAccountLoginSheet.swift",
        "import SwiftUI\nstruct CLIAccountLoginSheet: View { var body: some View { EmptyView() } }\n",
    );
}

#[test]
fn boundary_audit_treats_account_login_sheet_sections_as_ui_when_rule_is_present() {
    assert_accounts_rule(
        "accounts-login-sections-ui",
        "ui_view|App/SoloCodeApp/Sources/Accounts/CLIAccountLoginSheet/**|Account login sheet sections are SwiftUI presentation shells.\n",
        "App/SoloCodeApp/Sources/Accounts/CLIAccountLoginSheet/Sections/CLIAccountLoginSheet+Header.swift",
        "import SwiftUI\nstruct HeaderView: View { var body: some View { EmptyView() } }\n",
    );
}

#[test]
fn boundary_audit_treats_account_state_store_as_allowed_when_rule_is_present() {
    assert_accounts_rule(
        "accounts-state-store-allowlist",
        "binding_adapter|App/SoloCodeApp/Sources/Accounts/CodexStateStore.swift|Codex state store is a UI-facing status wrapper over provider detection.\n",
        "App/SoloCodeApp/Sources/Accounts/CodexStateStore.swift",
        "import Foundation\nfinal class CodexStateStore {}\n",
    );
}

fn assert_accounts_rule(label: &str, rule: &str, candidate: &str, candidate_source: &str) {
    let workspace = make_workspace(label);
    write_file(&workspace, "Config/validation/rust-cutover-swift-allowlist.txt", rule);
    write_file(&workspace, candidate, candidate_source);
    write_file(&workspace, "App/SoloCodeApp/Sources/Accounts/AccountUsageDashboardStore.swift", "import Foundation\nstruct DashboardStore {}\n");

    let response = dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
        workspace_root: workspace.to_string_lossy().to_string(),
        allowlist_path: workspace.join("Config/validation/rust-cutover-swift-allowlist.txt").to_string_lossy().to_string(),
        candidate_files: vec![candidate.to_string()],
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
    assert_eq!(report.enforced_prefix_counts.get("App/SoloCodeApp/Sources/Accounts"), Some(&1));
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
