use crate::boundary::allowlist::{matches, AllowlistRule};
use app_core_protocol::app_core::{BoundaryFindingStatus, SwiftBoundaryFinding, SwiftBoundaryKind};
use std::collections::BTreeSet;

const IGNORED_PREFIXES: &[&str] = &[
    ".build/",
    ".claude/",
    ".xcodebuild/",
    "build/",
    "DerivedData/",
    "Native/target/",
    "tmp/",
];

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BoundaryDisposition {
    Ignored,
    Allowed(SwiftBoundaryFinding),
    LegacyNonUi(SwiftBoundaryFinding),
    NewViolation(SwiftBoundaryFinding),
}

pub fn classify_path(
    path: &str,
    rules: &[AllowlistRule],
    new_files: &BTreeSet<String>,
) -> BoundaryDisposition {
    if !path.ends_with(".swift") || is_ignored(path) {
        return BoundaryDisposition::Ignored;
    }

    if let Some(rule) = rules.iter().find(|rule| matches(&rule.pattern, path)) {
        return BoundaryDisposition::Allowed(SwiftBoundaryFinding {
            path: path.to_string(),
            status: BoundaryFindingStatus::Allowed,
            kind: rule.kind.clone(),
            reason: rule.reason.clone(),
        });
    }

    let finding = SwiftBoundaryFinding {
        path: path.to_string(),
        status: if new_files.contains(path) {
            BoundaryFindingStatus::NewViolation
        } else {
            BoundaryFindingStatus::LegacyNonUi
        },
        kind: SwiftBoundaryKind::LegacyNonUi,
        reason: "File Swift non coperto da allowlist UI/bootstrap del cutover Rust.".to_string(),
    };

    if new_files.contains(path) {
        BoundaryDisposition::NewViolation(finding)
    } else {
        BoundaryDisposition::LegacyNonUi(finding)
    }
}

pub fn derive_domain(path: &str) -> String {
    for root in [
        "App/SoloCodeApp/Sources/",
        "Engine/CoderEngine/Sources/",
        "Sidebar/",
        "Tests/",
    ] {
        if let Some(rest) = path.strip_prefix(root) {
            let head = rest.split('/').next().unwrap_or("misc");
            return format!("{root}{head}");
        }
    }
    path.split('/').take(2).collect::<Vec<_>>().join("/")
}

fn is_ignored(path: &str) -> bool {
    path.contains("/.build/")
        || path.contains("/.xcodebuild/")
        || path.contains("/DerivedData/")
        || IGNORED_PREFIXES
            .iter()
            .any(|prefix| path.starts_with(prefix))
}

#[cfg(test)]
mod tests {
    use super::{classify_path, derive_domain, BoundaryDisposition};
    use crate::boundary::allowlist::AllowlistRule;
    use app_core_protocol::app_core::SwiftBoundaryKind;
    use std::collections::BTreeSet;

    #[test]
    fn classify_new_non_ui_swift_as_violation() {
        let mut new_files = BTreeSet::new();
        new_files.insert("App/SoloCodeApp/Sources/Runtime/NewLogic.swift".to_string());
        let disposition = classify_path(
            "App/SoloCodeApp/Sources/Runtime/NewLogic.swift",
            &[],
            &new_files,
        );
        assert!(matches!(disposition, BoundaryDisposition::NewViolation(_)));
    }

    #[test]
    fn classify_allowlisted_view_as_allowed() {
        let rules = vec![AllowlistRule {
            kind: SwiftBoundaryKind::UiView,
            pattern: "App/SoloCodeApp/Sources/**/Views/**".to_string(),
            reason: "UI".to_string(),
        }];
        let disposition = classify_path(
            "App/SoloCodeApp/Sources/Panels/CodeReview/Views/Foo.swift",
            &rules,
            &BTreeSet::new(),
        );
        assert!(matches!(disposition, BoundaryDisposition::Allowed(_)));
    }

    #[test]
    fn derive_domain_uses_product_subtree() {
        assert_eq!(
            derive_domain("Engine/CoderEngine/Sources/CodeReview/Foo.swift"),
            "Engine/CoderEngine/Sources/CodeReview"
        );
    }
}
