//! Costruzione di JSON Schema `object` per MCP `tools/list` (tipo, description, enum).

use serde_json::{json, Map, Value};

/// Proprietà di uno schema object con metadati opzionali per il modello.
#[derive(Clone, Copy, Debug)]
pub struct SchemaProp {
    pub name: &'static str,
    pub ty: &'static str,
    pub description: Option<&'static str>,
    pub enum_values: Option<&'static [&'static str]>,
}

impl SchemaProp {
    pub const fn with_desc(name: &'static str, description: &'static str) -> Self {
        Self {
            name,
            ty: "string",
            description: Some(description),
            enum_values: None,
        }
    }

    pub const fn with_enum(name: &'static str, description: &'static str, values: &'static [&'static str]) -> Self {
        Self {
            name,
            ty: "string",
            description: Some(description),
            enum_values: Some(values),
        }
    }

    pub const fn typed(name: &'static str, ty: &'static str, description: &'static str) -> Self {
        Self {
            name,
            ty,
            description: Some(description),
            enum_values: None,
        }
    }
}

pub fn object_from_props(props: &[SchemaProp], required: &[&str]) -> Value {
    let mut prop_map = Map::new();
    for p in props {
        let mut obj = Map::new();
        obj.insert("type".to_string(), Value::String(p.ty.to_string()));
        if let Some(d) = p.description {
            obj.insert("description".to_string(), Value::String(d.to_string()));
        }
        if let Some(en) = p.enum_values {
            let arr: Vec<Value> = en.iter().map(|s| Value::String((*s).to_string())).collect();
            obj.insert("enum".to_string(), Value::Array(arr));
        }
        prop_map.insert(p.name.to_string(), Value::Object(obj));
    }

    let required_values: Vec<Value> = required.iter().map(|s| Value::String((*s).to_string())).collect();
    let mut schema = Map::new();
    schema.insert("type".to_string(), Value::String("object".to_string()));
    schema.insert("properties".to_string(), Value::Object(prop_map));
    if !required_values.is_empty() {
        schema.insert("required".to_string(), Value::Array(required_values));
    }
    Value::Object(schema)
}

pub fn object_schema(properties: &[(&str, &str)], required: &[&str]) -> Value {
    let mut props = Map::new();
    for (name, kind) in properties {
        props.insert((*name).to_string(), json!({ "type": kind }));
    }
    let required_values: Vec<Value> = required.iter().map(|s| Value::String((*s).to_string())).collect();
    let mut schema = Map::new();
    schema.insert("type".to_string(), Value::String("object".to_string()));
    schema.insert("properties".to_string(), Value::Object(props));
    if !required_values.is_empty() {
        schema.insert("required".to_string(), Value::Array(required_values));
    }
    Value::Object(schema)
}

