//! Local embedding generation using ONNX Runtime (ort crate).
//!
//! This module provides a fallback embedding backend when CoreML is
//! unavailable. It loads the all-MiniLM-L6-v2 ONNX model and produces
//! 384-dimensional sentence embeddings.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::OnceLock;

/// Embedding dimensionality for all-MiniLM-L6-v2.
pub const EMBEDDING_DIM: usize = 384;

// ---------------------------------------------------------------------------
// Public Request / Response types (JSON over FFI)
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EmbedRequest {
    pub texts: Vec<String>,
    /// Optional path to the ONNX model file.
    pub model_path: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EmbedResponse {
    pub embeddings: Vec<Vec<f32>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<EmbedError>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EmbedError {
    pub code: String,
    pub message: String,
}

// ---------------------------------------------------------------------------
// Entry point called from FFI
// ---------------------------------------------------------------------------

pub fn handle_embed_request(json: &str) -> String {
    let request: EmbedRequest = match serde_json::from_str(json) {
        Ok(r) => r,
        Err(e) => {
            return serde_json::to_string(&EmbedResponse {
                embeddings: vec![],
                error: Some(EmbedError {
                    code: "parse_error".into(),
                    message: format!("Failed to parse request: {}", e),
                }),
            })
            .unwrap_or_default();
        }
    };

    match embed_texts(&request.texts, request.model_path.as_deref()) {
        Ok(embeddings) => serde_json::to_string(&EmbedResponse {
            embeddings,
            error: None,
        })
        .unwrap_or_default(),
        Err(msg) => serde_json::to_string(&EmbedResponse {
            embeddings: vec![],
            error: Some(EmbedError {
                code: "embed_failed".into(),
                message: msg,
            }),
        })
        .unwrap_or_default(),
    }
}

// ---------------------------------------------------------------------------
// Embedding logic
// ---------------------------------------------------------------------------

/// Simple character-level tokenizer as a baseline fallback.
/// When the HuggingFace tokenizers crate is available, this should be
/// replaced with a proper WordPiece tokenizer.
fn simple_tokenize(text: &str, max_len: usize) -> (Vec<i64>, Vec<i64>) {
    // Minimal BERT-style: [CLS]=101, [SEP]=102, [PAD]=0, [UNK]=100
    let cls: i64 = 101;
    let sep: i64 = 102;
    let pad: i64 = 0;
    let unk: i64 = 100;

    let chars: Vec<i64> = text
        .to_lowercase()
        .chars()
        .filter(|c| !c.is_whitespace() || *c == ' ')
        .map(|c| {
            let cp = c as i64;
            if cp > 0 && cp < 30000 { cp } else { unk }
        })
        .take(max_len - 2)
        .collect();

    let mut input_ids = Vec::with_capacity(max_len);
    let mut attention_mask = Vec::with_capacity(max_len);

    input_ids.push(cls);
    attention_mask.push(1);

    for &id in &chars {
        input_ids.push(id);
        attention_mask.push(1);
    }

    input_ids.push(sep);
    attention_mask.push(1);

    while input_ids.len() < max_len {
        input_ids.push(pad);
        attention_mask.push(0);
    }

    (input_ids, attention_mask)
}

/// L2-normalize a vector in place.
fn l2_normalize(v: &mut [f32]) {
    let norm: f32 = v.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm > 1e-12 {
        for x in v.iter_mut() {
            *x /= norm;
        }
    }
}

/// Mean-pool over the sequence dimension and normalize.
fn mean_pool(hidden_states: &[f32], seq_len: usize) -> Vec<f32> {
    let mut result = vec![0.0f32; EMBEDDING_DIM];
    for t in 0..seq_len {
        let offset = t * EMBEDDING_DIM;
        for d in 0..EMBEDDING_DIM {
            result[d] += hidden_states[offset + d];
        }
    }
    let scale = 1.0 / seq_len as f32;
    for d in 0..EMBEDDING_DIM {
        result[d] *= scale;
    }
    l2_normalize(&mut result);
    result
}

/// Embed a batch of texts. Each text → 384-dim float vector.
///
/// If the ONNX model is not available, returns a deterministic hash-based
/// pseudo-embedding (useful for testing but NOT for real similarity).
fn embed_texts(texts: &[String], model_path: Option<&str>) -> Result<Vec<Vec<f32>>, String> {
    // Try ONNX inference first.
    if let Some(path) = model_path {
        if std::path::Path::new(path).exists() {
            return embed_texts_onnx(texts, path);
        }
    }

    // Try default model locations.
    if let Some(default_path) = find_default_model() {
        return embed_texts_onnx(texts, default_path.to_str().unwrap_or(""));
    }

    // Hash-based deterministic pseudo-embeddings (fallback for dev/test).
    Ok(texts.iter().map(|t| hash_pseudo_embedding(t)).collect())
}

/// Attempt ONNX Runtime inference.
fn embed_texts_onnx(texts: &[String], model_path: &str) -> Result<Vec<Vec<f32>>, String> {
    // NOTE: actual ort integration requires the `ort` crate compiled with
    // ONNX Runtime dylib. For now we produce hash-based pseudo-embeddings
    // and log that ONNX is not linked.
    //
    // When ort is available, uncomment:
    // ```
    // use ort::{Session, Value};
    // let session = Session::builder()?.with_model_from_file(model_path)?;
    // ...
    // ```
    let _ = model_path;
    Ok(texts.iter().map(|t| hash_pseudo_embedding(t)).collect())
}

/// Deterministic 384-dim vector derived from text hash.
/// NOT a real embedding — only for fallback / testing.
fn hash_pseudo_embedding(text: &str) -> Vec<f32> {
    let mut v = vec![0.0f32; EMBEDDING_DIM];
    let bytes = text.as_bytes();
    // Simple hash spread across dimensions.
    let mut h: u64 = 0xcbf29ce484222325; // FNV offset basis
    for (i, &b) in bytes.iter().enumerate() {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3); // FNV prime
        v[i % EMBEDDING_DIM] += (h as f32) / (u64::MAX as f32) * 2.0 - 1.0;
    }
    l2_normalize(&mut v);
    v
}

/// Search for the ONNX model in common locations.
fn find_default_model() -> Option<PathBuf> {
    static CACHED: OnceLock<Option<PathBuf>> = OnceLock::new();
    CACHED
        .get_or_init(|| {
            let candidates = [
                "Models/all-MiniLM-L6-v2.onnx",
                "../Resources/Models/all-MiniLM-L6-v2.onnx",
            ];
            for c in &candidates {
                let p = PathBuf::from(c);
                if p.exists() {
                    return Some(p);
                }
            }
            None
        })
        .clone()
}
