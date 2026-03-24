use app_core_protocol::app_core::{
    AppCoreRequest, AppCoreResponse, BoundaryAuditRequest, BoundaryFindingStatus,
};
use app_core_rust::dispatch;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn boundary_audit_flags_new_non_ui_swift_file() {
    let workspace = make_workspace("new-non-ui");
    write_file(
        &workspace,
        "Config/validation/rust-cutover-swift-allowlist.txt",
        "ui_view|App/SoloCodeApp/Sources/**/Views/**|SwiftUI views only\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Panels/CodeReview/Views/AllowedView.swift",
        "import SwiftUI\nstruct AllowedView: View { var body: some View { EmptyView() } }\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Runtime/NewLogic.swift",
        "import Foundation\nfinal class NewLogic {}\n",
    );

    let response = dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
        workspace_root: workspace.to_string_lossy().to_string(),
        allowlist_path: workspace
            .join("Config/validation/rust-cutover-swift-allowlist.txt")
            .to_string_lossy()
            .to_string(),
        candidate_files: vec![
            "App/SoloCodeApp/Sources/Panels/CodeReview/Views/AllowedView.swift".to_string(),
            "App/SoloCodeApp/Sources/Runtime/NewLogic.swift".to_string(),
        ],
        new_files: vec!["App/SoloCodeApp/Sources/Runtime/NewLogic.swift".to_string()],
        enforce_legacy_zero_prefixes: vec![],
        legacy_non_ui_budget_by_prefix: Default::default(),
        include_missing_candidate_files: false,
    }))
    .expect("boundary dispatch should succeed");

    let AppCoreResponse::BoundaryAudit(report) = response;
    assert_eq!(report.summary.allowed_swift_files, 1);
    assert_eq!(report.summary.new_non_ui_files, 1);
    assert!(report.findings.iter().any(|finding| {
        finding.path == "App/SoloCodeApp/Sources/Runtime/NewLogic.swift"
            && finding.status == BoundaryFindingStatus::NewViolation
    }));
}

#[test]
fn boundary_audit_keeps_existing_non_ui_swift_as_legacy() {
    let workspace = make_workspace("legacy-non-ui");
    write_file(
        &workspace,
        "Config/validation/rust-cutover-swift-allowlist.txt",
        "ui_view|App/SoloCodeApp/Sources/**/Views/**|SwiftUI views only\n",
    );
    write_file(
        &workspace,
        "Engine/CoderEngine/Sources/CodeReview/LegacyService.swift",
        "import Foundation\nstruct LegacyService {}\n",
    );

    let response = dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
        workspace_root: workspace.to_string_lossy().to_string(),
        allowlist_path: workspace
            .join("Config/validation/rust-cutover-swift-allowlist.txt")
            .to_string_lossy()
            .to_string(),
        candidate_files: vec![
            "Engine/CoderEngine/Sources/CodeReview/LegacyService.swift".to_string()
        ],
        new_files: vec![],
        enforce_legacy_zero_prefixes: vec![],
        legacy_non_ui_budget_by_prefix: Default::default(),
        include_missing_candidate_files: false,
    }))
    .expect("boundary dispatch should succeed");

    let AppCoreResponse::BoundaryAudit(report) = response;
    assert_eq!(report.summary.legacy_non_ui_files, 1);
    assert_eq!(report.summary.new_non_ui_files, 0);
    assert_eq!(
        report
            .legacy_domain_counts
            .get("Engine/CoderEngine/Sources/CodeReview"),
        Some(&1)
    );
}

#[test]
fn boundary_audit_enforces_zero_legacy_for_review_prefixes() {
    let workspace = make_workspace("enforced-review-prefix");
    write_file(
        &workspace,
        "Config/validation/rust-cutover-swift-allowlist.txt",
        "ui_view|App/SoloCodeApp/Sources/**/Views/**|SwiftUI views only\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Panels/CodeReview/Views/AllowedView.swift",
        "import SwiftUI\nstruct AllowedView: View { var body: some View { EmptyView() } }\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Panels/CodeReview/Store/LegacyStore.swift",
        "import Foundation\nfinal class LegacyStore {}\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Panels/CodeReview/Coordinator/LegacyCoordinator.swift",
        "import Foundation\nstruct LegacyCoordinator {}\n",
    );

    let response = dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
        workspace_root: workspace.to_string_lossy().to_string(),
        allowlist_path: workspace
            .join("Config/validation/rust-cutover-swift-allowlist.txt")
            .to_string_lossy()
            .to_string(),
        candidate_files: vec![
            "App/SoloCodeApp/Sources/Panels/CodeReview/Views/AllowedView.swift".to_string(),
        ],
        new_files: vec![],
        enforce_legacy_zero_prefixes: vec!["App/SoloCodeApp/Sources/Panels/CodeReview".to_string()],
        legacy_non_ui_budget_by_prefix: Default::default(),
        include_missing_candidate_files: false,
    }))
    .expect("boundary dispatch should succeed");

    let AppCoreResponse::BoundaryAudit(report) = response;
    assert_eq!(report.summary.allowed_swift_files, 1);
    assert_eq!(report.summary.legacy_non_ui_files, 2);
    assert_eq!(report.summary.enforced_legacy_non_ui_files, 2);
    assert_eq!(
        report
            .enforced_prefix_counts
            .get("App/SoloCodeApp/Sources/Panels/CodeReview"),
        Some(&2)
    );
    assert_eq!(report.summary.budget_exceeded_legacy_non_ui_files, 2);
}

#[test]
fn boundary_audit_allows_tranche_when_legacy_budget_is_not_exceeded() {
    let workspace = make_workspace("budgeted-review-prefix");
    write_file(
        &workspace,
        "Config/validation/rust-cutover-swift-allowlist.txt",
        "ui_view|App/SoloCodeApp/Sources/**/Views/**|SwiftUI views only\n",
    );
    write_file(
        &workspace,
        "Engine/CoderEngine/Sources/CodeReview/LegacyAudit.swift",
        "import Foundation\nstruct LegacyAudit {}\n",
    );

    let response =
        dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
            workspace_root: workspace.to_string_lossy().to_string(),
            allowlist_path: workspace
                .join("Config/validation/rust-cutover-swift-allowlist.txt")
                .to_string_lossy()
                .to_string(),
            candidate_files: vec![
                "Engine/CoderEngine/Sources/CodeReview/LegacyAudit.swift".to_string()
            ],
            new_files: vec![],
            enforce_legacy_zero_prefixes: vec!["Engine/CoderEngine/Sources/CodeReview".to_string()],
            legacy_non_ui_budget_by_prefix: std::collections::BTreeMap::from([(
                "Engine/CoderEngine/Sources/CodeReview".to_string(),
                1,
            )]),
            include_missing_candidate_files: false,
        }))
        .expect("boundary dispatch should succeed");

    let AppCoreResponse::BoundaryAudit(report) = response;
    assert_eq!(report.summary.enforced_legacy_non_ui_files, 1);
    assert_eq!(report.summary.budget_exceeded_legacy_non_ui_files, 0);
    assert!(report.budget_exceeded_prefix_counts.is_empty());
}

#[test]
fn boundary_audit_ignores_missing_candidate_files() {
    let workspace = make_workspace("missing-candidate-file");
    write_file(
        &workspace,
        "Config/validation/rust-cutover-swift-allowlist.txt",
        "ui_view|App/SoloCodeApp/Sources/**/Views/**|SwiftUI views only\n",
    );
    write_file(
        &workspace,
        "App/SoloCodeApp/Sources/Panels/CodeReview/Store/StillPresent.swift",
        "import Foundation\nstruct StillPresent {}\n",
    );

    let response = dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
        workspace_root: workspace.to_string_lossy().to_string(),
        allowlist_path: workspace
            .join("Config/validation/rust-cutover-swift-allowlist.txt")
            .to_string_lossy()
            .to_string(),
        candidate_files: vec![
            "App/SoloCodeApp/Sources/Panels/CodeReview/Store/Deleted.swift".to_string(),
        ],
        new_files: vec![],
        enforce_legacy_zero_prefixes: vec!["App/SoloCodeApp/Sources/Panels/CodeReview".to_string()],
        legacy_non_ui_budget_by_prefix: std::collections::BTreeMap::from([(
            "App/SoloCodeApp/Sources/Panels/CodeReview".to_string(),
            1,
        )]),
        include_missing_candidate_files: false,
    }))
    .expect("boundary dispatch should succeed");

    let AppCoreResponse::BoundaryAudit(report) = response;
    assert_eq!(report.summary.legacy_non_ui_files, 1);
    assert_eq!(report.summary.budget_exceeded_legacy_non_ui_files, 0);
}

#[test]
fn boundary_audit_can_include_missing_candidate_files_when_requested() {
    let workspace = make_workspace("include-missing-candidate-file");
    write_file(
        &workspace,
        "Config/validation/rust-cutover-swift-allowlist.txt",
        "ui_view|App/SoloCodeApp/Sources/**/Views/**|SwiftUI views only\n",
    );

    let response = dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
        workspace_root: workspace.to_string_lossy().to_string(),
        allowlist_path: workspace
            .join("Config/validation/rust-cutover-swift-allowlist.txt")
            .to_string_lossy()
            .to_string(),
        candidate_files: vec![
            "App/SoloCodeApp/Sources/Panels/CodeReview/Store/Deleted.swift".to_string(),
        ],
        new_files: vec![],
        enforce_legacy_zero_prefixes: vec!["App/SoloCodeApp/Sources/Panels/CodeReview".to_string()],
        legacy_non_ui_budget_by_prefix: Default::default(),
        include_missing_candidate_files: true,
    }))
    .expect("boundary dispatch should succeed");

    let AppCoreResponse::BoundaryAudit(report) = response;
    assert_eq!(report.summary.legacy_non_ui_files, 1);
    assert_eq!(report.summary.enforced_legacy_non_ui_files, 1);
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
