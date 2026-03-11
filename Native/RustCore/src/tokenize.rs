use serde::{Deserialize, Serialize};
use std::collections::HashSet;

const STOP_WORDS: &[&str] = &[
    "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "how", "in", "is", "it",
    "of", "on", "or", "that", "the", "this", "to", "was", "where", "with",
];

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RustTokenizeRequestPayload {
    text: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RustTokenizeResponsePayload {
    hits: Vec<String>,
    error: Option<()>,
}

pub fn handle_tokenize_request(raw: &str) -> Result<String, String> {
    let payload: RustTokenizeRequestPayload =
        serde_json::from_str(raw).map_err(|err| format!("decode failed: {err}"))?;
    let tokens = tokenize_query(&payload.text);
    serde_json::to_string(&RustTokenizeResponsePayload { hits: tokens, error: None })
        .map_err(|err| format!("encode failed: {err}"))
}

pub fn tokenize_query(text: &str) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut output = Vec::new();
    for raw in text
        .split(|ch: char| !ch.is_alphanumeric())
        .filter(|part| part.len() >= 2)
    {
        for token in expand_token(raw) {
            if token.len() < 2 || STOP_WORDS.contains(&token.as_str()) {
                continue;
            }
            if seen.insert(token.clone()) {
                output.push(token);
            }
        }
    }
    output
}

fn expand_token(raw: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let lower = raw.to_lowercase();
    tokens.push(stem(&lower));

    let mut current = String::new();
    for ch in raw.chars() {
        if ch.is_uppercase() && !current.is_empty() {
            let lower = current.to_lowercase();
            tokens.push(stem(&lower));
            current.clear();
        }
        current.push(ch);
    }
    if !current.is_empty() {
        let lower = current.to_lowercase();
        tokens.push(stem(&lower));
    }

    tokens
}

fn stem(token: &str) -> String {
    for suffix in ["ing", "ers", "ies", "ed", "es", "s"] {
        if token.ends_with(suffix) && token.len() > suffix.len() + 2 {
            return token[..token.len() - suffix.len()].to_string();
        }
    }
    token.to_string()
}
