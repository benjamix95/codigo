//! Costruzione di JSON Schema `object` minimi per MCP `tools/list`.

use serde_json::{json, Map, Value};

pub fn object_schema(properties: &[(&str, &str)], required: &[&str]) -> Value {
    let mut props = Map::new();
    for (name, kind) in properties {
        props.insert((*name).to_string(), json!({ "type": kind }));
    }

    let required_values = required
        .iter()
        .map(|value| Value::String((*value).to_string()))
        .collect::<Vec<_>>();
    let mut schema = Map::new();
    schema.insert("type".to_string(), Value::String("object".to_string()));
    schema.insert("properties".to_string(), Value::Object(props));
    if !required_values.is_empty() {
        schema.insert("required".to_string(), Value::Array(required_values));
    }
    Value::Object(schema)
}
