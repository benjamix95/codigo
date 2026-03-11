use crate::review_value::{get_i64, get_str, normalize};
use serde_json::Value;
use std::collections::{HashMap, HashSet};

#[derive(Clone)]
pub struct PreparedIdentity {
    pub finding_id: String,
    pub domain: String,
    pub fingerprint: String,
    pub normalized_file_path: String,
    pub normalized_category: String,
    pub normalized_title: String,
    pub normalized_summary: String,
    pub line_start: Option<i64>,
}

#[derive(Default)]
pub struct IdentityIndex {
    exact_by_fingerprint: HashMap<String, String>,
    identities_by_id: HashMap<String, PreparedIdentity>,
    bucketed: HashMap<String, HashSet<String>>,
}

pub fn prepare(value: &Value) -> PreparedIdentity {
    PreparedIdentity {
        finding_id: get_str(value, "id").unwrap_or_default().to_string(),
        domain: get_str(value, "domain").unwrap_or("bug").to_string(),
        fingerprint: get_str(value, "findingFingerprint").unwrap_or_default().to_string(),
        normalized_file_path: normalize(get_str(value, "filePath").unwrap_or_default()),
        normalized_category: normalize(get_str(value, "category").unwrap_or_default()),
        normalized_title: normalize(get_str(value, "title").unwrap_or_default()),
        normalized_summary: normalize(get_str(value, "summary").unwrap_or_default()),
        line_start: get_i64(value, "lineStart"),
    }
}

impl IdentityIndex {
    pub fn insert(&mut self, identity: PreparedIdentity) {
        self.exact_by_fingerprint.insert(
            format!("{}|{}", identity.domain, identity.fingerprint),
            identity.finding_id.clone(),
        );
        for bucket in bucket_keys(&identity) {
            self.bucketed.entry(bucket).or_default().insert(identity.finding_id.clone());
        }
        self.identities_by_id.insert(identity.finding_id.clone(), identity);
    }

    pub fn exact_duplicate_id(&self, identity: &PreparedIdentity) -> Option<String> {
        self.exact_by_fingerprint
            .get(&format!("{}|{}", identity.domain, identity.fingerprint))
            .cloned()
    }

    pub fn candidates(&self, identity: &PreparedIdentity) -> Vec<PreparedIdentity> {
        let mut ids = HashSet::new();
        for bucket in bucket_keys(identity) {
            if let Some(found) = self.bucketed.get(&bucket) {
                ids.extend(found.iter().cloned());
            }
        }
        ids.into_iter()
            .filter_map(|id| self.identities_by_id.get(&id).cloned())
            .collect()
    }
}

pub fn similarity_score(lhs: &PreparedIdentity, rhs: &PreparedIdentity) -> f64 {
    let mut score = 0.0;
    if lhs.normalized_file_path == rhs.normalized_file_path {
        score += 0.35;
    }
    if lhs.normalized_category == rhs.normalized_category {
        score += 0.20;
    }
    if compatible_lines(lhs.line_start, rhs.line_start) {
        score += 0.15;
    }
    if lhs.normalized_title == rhs.normalized_title {
        score += 0.15;
    }
    if lhs.normalized_summary == rhs.normalized_summary {
        score += 0.15;
    }
    score
}

pub fn find_duplicate(
    candidate: &Value,
    existing: &[Value],
    minimum_score: f64,
) -> Option<Value> {
    let candidate_identity = prepare(candidate);
    let mut index = IdentityIndex::default();
    for finding in existing
        .iter()
        .filter(|finding| get_str(finding, "domain") == Some(candidate_identity.domain.as_str()))
    {
        index.insert(prepare(finding));
    }
    if let Some(existing_finding_id) = index.exact_duplicate_id(&candidate_identity) {
        return Some(serde_json::json!({
            "existingFindingId": existing_finding_id,
            "isExactDuplicate": true,
            "score": 1.0
        }));
    }

    let mut best_match: Option<(String, bool, f64)> = None;
    for existing_identity in index.candidates(&candidate_identity) {
        let score = similarity_score(&candidate_identity, &existing_identity);
        if score < minimum_score {
            continue;
        }
        let match_tuple = (
            existing_identity.finding_id.clone(),
            existing_identity.fingerprint == candidate_identity.fingerprint,
            score,
        );
        if should_replace_best_match(&match_tuple, best_match.as_ref()) {
            best_match = Some(match_tuple);
        }
    }

    best_match.map(|(existing_finding_id, is_exact_duplicate, score)| {
        serde_json::json!({
            "existingFindingId": existing_finding_id,
            "isExactDuplicate": is_exact_duplicate,
            "score": score
        })
    })
}

fn compatible_lines(lhs: Option<i64>, rhs: Option<i64>) -> bool {
    match (lhs, rhs) {
        (Some(lhs), Some(rhs)) => (lhs - rhs).abs() <= 3,
        _ => false,
    }
}

fn bucket_keys(identity: &PreparedIdentity) -> [String; 3] {
    [
        format!("{}|{}", identity.domain, identity.normalized_file_path),
        format!("{}|{}", identity.domain, identity.normalized_title),
        format!("{}|{}", identity.domain, identity.normalized_summary),
    ]
}

fn should_replace_best_match(
    candidate: &(String, bool, f64),
    current: Option<&(String, bool, f64)>,
) -> bool {
    match current {
        None => true,
        Some(current) => {
            if candidate.1 != current.1 {
                candidate.1 && !current.1
            } else {
                candidate.2 > current.2
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn identity_similarity_matches_swift_weights() {
        let lhs = prepare(&json!({
            "id": "a",
            "domain": "bug",
            "findingFingerprint": "a",
            "filePath": "A.swift",
            "category": "correctness",
            "title": "Race condition in stream retry",
            "summary": "Late retry emits duplicate terminal event",
            "lineStart": 24
        }));
        let rhs = prepare(&json!({
            "id": "b",
            "domain": "bug",
            "findingFingerprint": "b",
            "filePath": "A.swift",
            "category": "correctness",
            "title": "Retry path can race with terminal callback",
            "summary": "Late retry emits duplicate terminal event",
            "lineStart": 26
        }));
        assert!((similarity_score(&lhs, &rhs) - 0.85).abs() < 0.0001);
    }
}
