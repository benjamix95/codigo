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
        candidate_files: vec!["Engine/CoderEngine/Sources/CodeReview/LegacyService.swift".to_string()],
        new_files: vec![],
    }))
    .expect("boundary dispatch should succeed");

    let AppCoreResponse::BoundaryAudit(report) = response;
    assert_eq!(report.summary.legacy_non_ui_files, 1);
    assert_eq!(report.summary.new_non_ui_files, 0);
    assert_eq!(
        report.legacy_domain_counts.get("Engine/CoderEngine/Sources/CodeReview"),
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
