use crate::tokenize::tokenize_query;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RustSearchRequestPayload {
    query: RustSearchQueryPayload,
    snapshot: RustSearchSnapshotPayload,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RustSearchQueryPayload {
    query: String,
    target_directories: Vec<String>,
    num_results: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RustSearchSnapshotPayload {
    chunks: Vec<RustSearchChunkPayload>,
    inverted_index: HashMap<String, Vec<String>>,
    term_frequencies: HashMap<String, HashMap<String, i32>>,
    doc_lengths: HashMap<String, i32>,
    avg_doc_length: f64,
    total_docs: usize,
    k1: f64,
    b: f64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RustSearchChunkPayload {
    chunk_id: String,
    file_path: String,
    scope: String,
    kind: String,
    content: String,
    symbol_names: Vec<String>,
    contextualized_text: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RustSearchResponsePayload {
    pub hits: Vec<RustSearchHitPayload>,
    pub error: Option<RustSearchErrorPayload>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RustSearchHitPayload {
    pub chunk_id: String,
    pub score: f64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RustSearchErrorPayload {
    pub code: String,
    pub message: String,
}

impl RustSearchResponsePayload {
    pub fn error(code: &str, message: &str) -> Self {
        Self {
            hits: Vec::new(),
            error: Some(RustSearchErrorPayload {
                code: code.to_string(),
                message: message.to_string(),
            }),
        }
    }
}

pub fn handle_search_request(raw: &str) -> Result<RustSearchResponsePayload, String> {
    let payload: RustSearchRequestPayload =
        serde_json::from_str(raw).map_err(|err| format!("decode failed: {err}"))?;

    let chunks_by_id: HashMap<&str, &RustSearchChunkPayload> = payload
        .snapshot
        .chunks
        .iter()
        .map(|chunk| (chunk.chunk_id.as_str(), chunk))
        .collect();

    let (positive_query, negative_tokens) = split_negations(&payload.query.query);
    let query_tokens = tokenize_query(&positive_query);
    if query_tokens.is_empty() || payload.snapshot.total_docs == 0 {
        return Ok(RustSearchResponsePayload {
            hits: Vec::new(),
            error: None,
        });
    }

    let mut scores: HashMap<&str, f64> = HashMap::new();
    let unique_tokens: HashSet<&str> = query_tokens.iter().map(String::as_str).collect();
    for token in unique_tokens {
        let Some(postings) = payload.snapshot.inverted_index.get(token) else {
            continue;
        };
        let df = postings.len() as f64;
        let n = payload.snapshot.total_docs as f64;
        let idf = ((n - df + 0.5) / (df + 0.5) + 1.0).ln();

        for chunk_id in postings {
            let Some(chunk) = chunks_by_id.get(chunk_id.as_str()) else {
                continue;
            };
            if !payload.query.target_directories.is_empty()
                && !payload
                    .query
                    .target_directories
                    .iter()
                    .any(|prefix| chunk.file_path.starts_with(prefix))
            {
                continue;
            }
            let tf = payload
                .snapshot
                .term_frequencies
                .get(chunk_id)
                .and_then(|terms| terms.get(token))
                .copied()
                .unwrap_or(0) as f64;
            let dl = payload
                .snapshot
                .doc_lengths
                .get(chunk_id)
                .copied()
                .unwrap_or(1) as f64;
            let avg_dl = payload.snapshot.avg_doc_length.max(1.0);
            let tf_norm = (tf * (payload.snapshot.k1 + 1.0))
                / (tf
                    + payload.snapshot.k1
                        * (1.0 - payload.snapshot.b + payload.snapshot.b * dl / avg_dl));
            *scores.entry(chunk_id.as_str()).or_insert(0.0) += idf * tf_norm;
        }
    }

    let query_lower = positive_query.to_lowercase();
    for (chunk_id, score) in scores.iter_mut() {
        if let Some(chunk) = chunks_by_id.get(chunk_id) {
            *score += score_bonus(chunk, &query_lower, &query_tokens);
        }
    }

    if !negative_tokens.is_empty() {
        let negative_set: HashSet<String> = negative_tokens.into_iter().collect();
        // Use the inverted index to find chunks containing negative tokens,
        // avoiding expensive per-chunk re-tokenization (O(k*p) vs O(n*m)).
        let mut excluded_chunk_ids: HashSet<&str> = HashSet::new();
        for neg_token in &negative_set {
            if let Some(postings) = payload.snapshot.inverted_index.get(neg_token.as_str()) {
                for chunk_id in postings {
                    excluded_chunk_ids.insert(chunk_id.as_str());
                }
            }
        }
        scores.retain(|chunk_id, _| !excluded_chunk_ids.contains(chunk_id));
    }

    let mut ranked: Vec<RustSearchHitPayload> = scores
        .into_iter()
        .map(|(chunk_id, score)| RustSearchHitPayload {
            chunk_id: chunk_id.to_string(),
            score,
        })
        .collect();
    ranked.sort_by(|lhs, rhs| {
        rhs.score
            .partial_cmp(&lhs.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    ranked.truncate(payload.query.num_results);

    Ok(RustSearchResponsePayload {
        hits: ranked,
        error: None,
    })
}

fn split_negations(query: &str) -> (String, Vec<String>) {
    let mut positive = Vec::new();
    let mut negative = Vec::new();
    for word in query.split_whitespace() {
        let stripped = word.trim_start_matches('-');
        if stripped.len() < word.len() && !stripped.is_empty() {
            negative.extend(tokenize_query(stripped));
        } else {
            positive.push(word);
        }
    }
    (positive.join(" "), negative)
}

fn score_bonus(chunk: &RustSearchChunkPayload, query_lower: &str, query_tokens: &[String]) -> f64 {
    let mut bonus = 0.0;
    for symbol in &chunk.symbol_names {
        let lower = symbol.to_lowercase();
        if lower == query_lower {
            bonus += 10.0;
        } else if lower.contains(query_lower) {
            bonus += 5.0;
        }
        for token in query_tokens.iter().filter(|token| token.len() >= 3) {
            if lower.contains(token) {
                bonus += 1.5;
            }
        }
    }

    let scope_lower = chunk.scope.to_lowercase();
    for token in query_tokens {
        if scope_lower.contains(token) {
            bonus += 1.0;
        }
    }

    let file_name = chunk
        .file_path
        .rsplit('/')
        .next()
        .unwrap_or_default()
        .to_lowercase();
    if file_name.contains(query_lower) {
        bonus += 2.0;
    }

    match chunk.kind.as_str() {
        "class" | "struct" | "protocol" | "enum" | "interface" => bonus += 1.0,
        "function" | "method" => bonus += 0.5,
        "property" | "constant" => bonus += 0.2,
        _ => {}
    }

    if chunk.content.contains("///")
        || chunk.content.contains("/**")
        || chunk.content.contains("# ")
    {
        bonus += 0.25;
    }

    bonus
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_test_payload(query: &str) -> String {
        serde_json::json!({
            "query": {
                "query": query,
                "targetDirectories": [],
                "numResults": 10
            },
            "snapshot": {
                "chunks": [
                    {
                        "chunkId": "c1",
                        "filePath": "foo.swift",
                        "scope": "Foo",
                        "kind": "function",
                        "content": "func hello() { }",
                        "symbolNames": ["hello"],
                        "contextualizedText": "hello world greeting"
                    },
                    {
                        "chunkId": "c2",
                        "filePath": "bar.swift",
                        "scope": "Bar",
                        "kind": "function",
                        "content": "func goodbye() { }",
                        "symbolNames": ["goodbye"],
                        "contextualizedText": "goodbye farewell parting"
                    },
                    {
                        "chunkId": "c3",
                        "filePath": "baz.swift",
                        "scope": "Baz",
                        "kind": "function",
                        "content": "func greet() { hello() }",
                        "symbolNames": ["greet"],
                        "contextualizedText": "hello greet welcome"
                    }
                ],
                "invertedIndex": {
                    "hello": ["c1", "c3"],
                    "world": ["c1"],
                    "greet": ["c3"],
                    "goodby": ["c2"],
                    "farewell": ["c2"],
                    "welcom": ["c3"]
                },
                "termFrequencies": {
                    "c1": {"hello": 1, "world": 1},
                    "c2": {"goodby": 1, "farewell": 1},
                    "c3": {"hello": 1, "greet": 1, "welcom": 1}
                },
                "docLengths": {"c1": 3, "c2": 3, "c3": 3},
                "avgDocLength": 3.0,
                "totalDocs": 3,
                "k1": 1.2,
                "b": 0.75
            }
        })
        .to_string()
    }

    #[test]
    fn test_negative_query_excludes_via_inverted_index() {
        // Query "hello -goodby" should return c1,c3 but NOT c2
        let payload = make_test_payload("hello -goodbye");
        let result = handle_search_request(&payload).unwrap();
        assert!(result.error.is_none());
        let ids: Vec<&str> = result.hits.iter().map(|h| h.chunk_id.as_str()).collect();
        assert!(ids.contains(&"c1"), "c1 should be in results");
        assert!(ids.contains(&"c3"), "c3 should be in results");
        assert!(
            !ids.contains(&"c2"),
            "c2 should be excluded by negative query"
        );
    }

    #[test]
    fn test_negative_query_empty_negatives_returns_all() {
        let payload = make_test_payload("hello");
        let result = handle_search_request(&payload).unwrap();
        assert!(result.error.is_none());
        // "hello" tokens match c1 and c3 via inverted index
        let ids: Vec<&str> = result.hits.iter().map(|h| h.chunk_id.as_str()).collect();
        assert!(ids.contains(&"c1"));
        assert!(ids.contains(&"c3"));
    }

    #[test]
    fn test_split_negations_basic() {
        let (pos, neg) = split_negations("hello -world foo");
        assert_eq!(pos, "hello foo");
        assert!(!neg.is_empty());
    }

    #[test]
    fn test_split_negations_no_negatives() {
        let (pos, neg) = split_negations("hello world");
        assert_eq!(pos, "hello world");
        assert!(neg.is_empty());
    }
}
