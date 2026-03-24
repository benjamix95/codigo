use super::config::resolve_config_from_payload;
use super::models::{ReviewCommandConfig, ReviewCommandMutationResponse};
use super::mutator_support::event_with_reference_timestamp;
use serde_json::{json, Value};
use std::collections::HashMap;

pub fn configure_snapshot(
    events: &mut Vec<Value>,
    payload: &HashMap<String, String>,
    current_config: &mut Option<ReviewCommandConfig>,
    timestamp: f64,
) -> Result<(), ReviewCommandMutationResponse> {
    let Some(base_config) = current_config.clone() else {
        return Err(ReviewCommandMutationResponse::error(
            "Snapshot config is missing",
        ));
    };
    let updated_config = resolve_config_from_payload(payload, base_config);
    *current_config = Some(updated_config.clone());
    events.push(event_with_reference_timestamp(
        "config_updated",
        format!(
            "Config updated (workers={}, rounds={}, analysis_only={})",
            updated_config.max_workers, updated_config.max_rounds, updated_config.analysis_only
        ),
        json!({
            "max_workers": updated_config.max_workers.to_string(),
            "max_rounds": updated_config.max_rounds.to_string(),
            "analysis_backend": updated_config.analysis_backend,
            "execution_backend": updated_config.execution_backend,
            "analysis_only": if updated_config.analysis_only { "true" } else { "false" },
        }),
        timestamp,
    ));
    Ok(())
}
