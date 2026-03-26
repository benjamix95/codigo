//! Router verso schemi review / security / bughunter (moduli dedicati).

use crate::tool_schema_workflow_bughunter::bughunter_tool_schema;
use crate::tool_schema_workflow_review::review_tool_schema;
use crate::tool_schema_workflow_security::security_tool_schema;
use serde_json::Value;

pub fn verified_workflow_schema(name: &str) -> Option<Value> {
    if name.starts_with("coderide_review_") {
        return Some(review_tool_schema(name));
    }
    if name.starts_with("coderide_security_") {
        return Some(security_tool_schema(name));
    }
    if name.starts_with("coderide_bughunter_") {
        return Some(bughunter_tool_schema(name));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::verified_workflow_schema;

    #[test]
    fn workflow_tools_from_catalog_have_non_empty_properties() {
        let raw = include_str!("tool_names.txt");
        for line in raw.lines().map(str::trim).filter(|l| !l.is_empty()) {
            if !(line.starts_with("coderide_review_")
                || line.starts_with("coderide_security_")
                || line.starts_with("coderide_bughunter_"))
            {
                continue;
            }
            let schema = verified_workflow_schema(line)
                .unwrap_or_else(|| panic!("missing workflow schema for {line}"));
            let props = schema
                .get("properties")
                .and_then(|p| p.as_object())
                .unwrap_or_else(|| panic!("{line}: no properties object"));
            assert!(!props.is_empty(), "{line}: empty properties");
        }
    }

    #[test]
    fn workflow_high_traffic_props_have_descriptions() {
        let schema = verified_workflow_schema("coderide_review_start").unwrap();
        let scope = schema["properties"]["scope"].as_object().unwrap();
        assert!(scope.get("description").is_some());
        assert!(scope.get("enum").is_some());
    }
}
