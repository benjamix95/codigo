use super::{
    clean_patterns_for_type, debug_test_timeout_ms, generated_debug_instrumentation,
    generated_debug_marker,
};
use serde_json::json;
use std::collections::BTreeMap;

#[test]
fn debug_marker_log_generation_is_stable() {
    let generated = generated_debug_marker("log", "checkpoint", "value", " [H:abcd]", 42).unwrap();
    assert!(generated.contains("[DEBUG:log]"));
    assert!(generated.contains("checkpoint"));
    assert!(generated.contains("[H:abcd]"));
}

#[test]
fn debug_clean_logs_only_matches_log_markers() {
    let patterns = clean_patterns_for_type("logs").unwrap();
    assert_eq!(patterns, vec!["[debug:log]", "[debug:instrument-log]"]);
}

#[test]
fn debug_clean_conditional_breaks_match_conditional_instrumentation() {
    let patterns = clean_patterns_for_type("conditional_break").unwrap();
    assert_eq!(patterns, vec!["[debug:instrument-conditional]"]);
}

#[test]
fn debug_instrument_assert_uses_condition_when_present() {
    let generated = generated_debug_instrumentation(
        "assert",
        "value",
        "Value positive",
        Some("value > 0"),
        "",
        27,
    )
    .unwrap();
    assert!(generated.contains("assert(value > 0"));
    assert!(generated.contains("[DEBUG:instrument-assert]"));
}

#[test]
fn debug_test_timeout_is_clamped() {
    let mut arguments = BTreeMap::new();
    arguments.insert("timeout_ms".to_string(), json!("9999999"));
    assert_eq!(debug_test_timeout_ms(&arguments), 900_000);
}
