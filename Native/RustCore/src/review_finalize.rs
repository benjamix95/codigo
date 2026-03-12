use serde_json::Value;

pub fn select_patch_finalization_targets(snapshot: &Value) -> Value {
    let finding_ids = snapshot
        .get("findings")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|finding| {
            let finding_id = finding.get("id").and_then(Value::as_str)?;
            let is_verified = finding.get("verifiedAt").is_some()
                || finding.get("verificationReport").and_then(Value::as_str).is_some();
            if !is_verified {
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

fn is_patch_ready(patch: &Value) -> bool {
    let verify_status = patch.get("verifyStatus").and_then(Value::as_str);
    let status = patch.get("status").and_then(Value::as_str);
    verify_status == Some("verified")
        && matches!(status, Some("verified") | Some("applied") | Some("pr_opened") | Some("merged"))
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
}
