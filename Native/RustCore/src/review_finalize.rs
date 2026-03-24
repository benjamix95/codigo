use serde_json::Value;

pub fn select_patch_finalization_targets(snapshot: &Value) -> Value {
    select_patch_finalization_targets_filtered(snapshot, None, false)
}

pub fn select_auto_prepare_targets(snapshot: &Value, origin_filter: Option<&str>) -> Value {
    select_patch_finalization_targets_filtered(snapshot, origin_filter, true)
}

fn select_patch_finalization_targets_filtered(
    snapshot: &Value,
    origin_filter: Option<&str>,
    require_missing_patch_artifact: bool,
) -> Value {
    let allowed_origins = parse_allowed_origins(origin_filter);
    let finding_ids = snapshot
        .get("findings")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|finding| {
            let finding_id = finding.get("id").and_then(Value::as_str)?;
            if !allowed_origins.is_empty() {
                let origin = finding.get("origin").and_then(Value::as_str)?;
                if !allowed_origins.iter().any(|candidate| candidate == origin) {
                    return None;
                }
            }
            let is_verified = finding.get("verifiedAt").is_some()
                || finding
                    .get("verificationReport")
                    .and_then(Value::as_str)
                    .is_some();
            if !is_verified {
                return None;
            }
            if require_missing_patch_artifact
                && finding
                    .get("patchArtifactId")
                    .and_then(Value::as_str)
                    .is_some()
            {
                return None;
            }
            let patch = snapshot
                .get("patches")
                .and_then(Value::as_array)
                .and_then(|patches| {
                    patches.iter().find(|patch| {
                        patch.get("findingId").and_then(Value::as_str) == Some(finding_id)
                    })
                });
            let patch_ready = patch.map(is_patch_ready).unwrap_or(false);
            if patch_ready {
                None
            } else {
                Some(Value::String(finding_id.to_string()))
            }
        })
        .collect::<Vec<_>>();
    Value::Array(finding_ids)
}

fn parse_allowed_origins(origin_filter: Option<&str>) -> Vec<String> {
    origin_filter
        .unwrap_or_default()
        .split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
        .collect()
}

fn is_patch_ready(patch: &Value) -> bool {
    let verify_status = patch.get("verifyStatus").and_then(Value::as_str);
    let status = patch.get("status").and_then(Value::as_str);
    verify_status == Some("verified")
        && matches!(
            status,
            Some("verified") | Some("applied") | Some("pr_opened") | Some("merged")
        )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn selects_only_verified_findings_without_ready_patch() {
        let targets = select_patch_finalization_targets(&json!({
            "findings": [
                {"id": "f1", "verifiedAt": "2026-03-12T00:00:00Z"},
                {"id": "f2", "verificationReport": "ok"},
                {"id": "f3"}
            ],
            "patches": [
                {"findingId": "f2", "verifyStatus": "verified", "status": "verified"}
            ]
        }));
        assert_eq!(targets.as_array().map(|items| items.len()), Some(1));
        assert_eq!(targets[0].as_str(), Some("f1"));
    }

    #[test]
    fn selects_auto_prepare_targets_with_origin_filter_and_missing_patch_artifact() {
        let targets = select_auto_prepare_targets(
            &json!({
                "findings": [
                    {"id": "f1", "verifiedAt": "2026-03-12T00:00:00Z", "origin": "bugHunter", "patchArtifactId": null},
                    {"id": "f2", "verificationReport": "ok", "origin": "reviewer", "patchArtifactId": null},
                    {"id": "f3", "verificationReport": "ok", "origin": "bugHunter", "patchArtifactId": "patch-3"},
                    {"id": "f4", "origin": "bugHunter", "patchArtifactId": null}
                ],
                "patches": []
            }),
            Some("bugHunter"),
        );
        assert_eq!(targets.as_array().map(|items| items.len()), Some(1));
        assert_eq!(targets[0].as_str(), Some("f1"));
    }
}
