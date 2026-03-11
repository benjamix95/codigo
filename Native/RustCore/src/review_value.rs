use serde_json::{Map, Value};

pub fn get_str<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value.get(key)?.as_str()
}

pub fn get_i64(value: &Value, key: &str) -> Option<i64> {
    value.get(key)?.as_i64()
}

pub fn get_bool(value: &Value, key: &str) -> bool {
    value.get(key).and_then(Value::as_bool).unwrap_or(false)
}

pub fn set_string_array(value: &mut Value, key: &str, items: Vec<String>) {
    let array = items.into_iter().map(Value::String).collect();
    ensure_object(value).insert(key.to_string(), Value::Array(array));
}

pub fn set_optional_string(value: &mut Value, key: &str, item: Option<String>) {
    let object = ensure_object(value);
    match item {
        Some(item) => {
            object.insert(key.to_string(), Value::String(item));
        }
        None => {
            object.insert(key.to_string(), Value::Null);
        }
    }
}

pub fn normalize(text: &str) -> String {
    text.trim().to_lowercase()
}

pub fn ensure_object(value: &mut Value) -> &mut Map<String, Value> {
    if !value.is_object() {
        *value = Value::Object(Map::new());
    }
    value.as_object_mut().expect("value must be an object")
}
