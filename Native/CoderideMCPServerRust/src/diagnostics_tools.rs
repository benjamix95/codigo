use app_core_protocol::mcp::CallToolResult;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Instant, SystemTime};
#[cfg(unix)]
use std::os::unix::process::ExitStatusExt;

pub fn handle(
    name: &str,
    workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    match name {
        "coderide_git_diff" => Some(git_diff(workspace, arguments)),
        "coderide_diagnostics" => Some(diagnostics(workspace, arguments)),
        "coderide_read_lints" => Some(read_lints(workspace)),
        "coderide_semantic_search" => Some(semantic_search(workspace, arguments)),
        _ => None,
    }
}

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PersistedSemanticChunk {
    id: String,
    file_path: String,
    start_line: usize,
    end_line: usize,
    content: String,
    scope: String,
    kind: String,
    language: String,
    #[serde(default)]
    symbol_names: Vec<String>,
    #[serde(default)]
    imports: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RustCoreSearchRequestPayload {
    query: RustCoreSearchQueryPayload,
    snapshot: RustCoreSearchSnapshotPayload,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RustCoreSearchQueryPayload {
    query: String,
    target_directories: Vec<String>,
    num_results: usize,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RustCoreSearchSnapshotPayload {
    chunks: Vec<RustCoreChunkPayload>,
    inverted_index: HashMap<String, Vec<String>>,
    term_frequencies: HashMap<String, HashMap<String, i32>>,
    doc_lengths: HashMap<String, i32>,
    avg_doc_length: f64,
    total_docs: usize,
    k1: f64,
    b: f64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RustCoreChunkPayload {
    chunk_id: String,
    file_path: String,
    scope: String,
    kind: String,
    content: String,
    symbol_names: Vec<String>,
    contextualized_text: String,
}

#[derive(Clone)]
struct SemanticHitLine {
    rendered: String,
    confidence: f64,
}

struct ParsedSemanticChunksCache {
    cache_path: PathBuf,
    mtime: SystemTime,
    len: u64,
    chunks: Arc<Vec<PersistedSemanticChunk>>,
}

static PARSED_SEMANTIC_CHUNKS_CACHE: Mutex<Option<ParsedSemanticChunksCache>> = Mutex::new(None);

fn git_diff(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let scope = crate::search_tools::string_arg(arguments, "path");
    let args = if scope.is_empty() {
        vec!["diff", "--", "."]
    } else {
        vec!["diff", "--", scope.as_str()]
    };
    shell_text("git", &args, workspace)
}

fn diagnostics(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let manager = crate::search_tools::string_arg(arguments, "manager").to_lowercase();
    let (command, args): (&str, Vec<&str>) =
        if manager == "cargo" || workspace.join("Cargo.toml").exists() {
            ("cargo", vec!["check"])
        } else if workspace.join("Package.swift").exists() {
            ("swift", vec!["build"])
        } else if workspace.join("package.json").exists() {
            ("npm", vec!["run", "build"])
        } else {
            ("swift", vec!["build"])
        };
    shell_text(command, &args, workspace)
}

fn read_lints(workspace: &Path) -> CallToolResult {
    if workspace.join("Cargo.toml").exists() {
        return shell_text("cargo", &["check", "--message-format=short"], workspace);
    }
    if workspace.join("Package.swift").exists() {
        return shell_text("swift", &["build", "--build-tests"], workspace);
    }
    CallToolResult::error("No recognized linter found. Supported: Swift, Cargo.")
}

/// Semantic search with multi-term scoring.
/// Prefers the persisted semantic chunk index when available, and falls back
/// to lexical multi-term scoring when no index cache is available yet.
fn semantic_search(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = crate::search_tools::string_arg(arguments, "query");
    if query.is_empty() {
        return CallToolResult::error("Missing 'query' argument");
    }

    // Resolve path scope from multiple aliases.
    let path_scope = resolved_path_scope_for_search(arguments);
    let search_dir = if path_scope.is_empty() {
        workspace.to_path_buf()
    } else {
        workspace.join(&path_scope)
    };

    // File type filter.
    let file_type = crate::search_tools::string_arg(arguments, "fileType");

    // Result limit.
    let limit = crate::search_tools::int_arg(arguments, "num_results")
        .or_else(|| crate::search_tools::int_arg(arguments, "limit"))
        .unwrap_or(50) as usize;
    let min_confidence = crate::search_tools::float_arg(arguments, "min_confidence")
        .unwrap_or(0.45)
        .clamp(0.0, 1.0);
    let show_scoring = crate::search_tools::bool_arg(arguments, "show_scoring").unwrap_or(false);
    let strict_scope = crate::search_tools::bool_arg(arguments, "strict_scope").unwrap_or(false);
    let target_directories = target_directories_for_search(arguments, &path_scope);

    if strict_scope && target_directories.is_empty() {
        return CallToolResult::error(
            "semantic_search strict_scope=true requires pathScope/path/target_directories"
        );
    }

    if let Some(index_output) = semantic_search_via_persisted_index(
        workspace,
        &query,
        &target_directories,
        &file_type,
        limit,
        min_confidence,
        show_scoring,
    ) {
        return CallToolResult::text(index_output);
    }

    let lexical_hits = lexical_semantic_search(
        &search_dir,
        &query,
        &file_type,
        limit,
        min_confidence,
        show_scoring,
    );
    if lexical_hits.is_empty() {
        return CallToolResult::text("No results.");
    }
    CallToolResult::text(
        lexical_hits
            .into_iter()
            .take(limit)
            .map(|hit| hit.rendered)
            .collect::<Vec<_>>()
            .join("\n")
    )
}

/// Run a single-term rg search (fast path).
fn run_single_term_search(
    search_dir: &Path,
    term: &str,
    file_type: &str,
    limit: usize,
) -> Vec<SemanticHitLine> {
    let mut rg_args: Vec<String> = vec![
        "-n".into(),
        "--no-heading".into(),
        "--smart-case".into(),
    ];
    if !file_type.is_empty() {
        rg_args.push("--type".into());
        rg_args.push(file_type.to_string());
    }
    rg_args.push(term.to_string());

    let rg_refs: Vec<&str> = rg_args.iter().map(|s| s.as_str()).collect();
    match crate::search_tools::run_rg(search_dir, &rg_refs) {
        Ok(stdout) if stdout.is_empty() => Vec::new(),
        Ok(stdout) => stdout
            .lines()
            .take(limit)
            .map(|line| SemanticHitLine {
                rendered: format!("[conf=1.00] {line}"),
                confidence: 1.0,
            })
            .collect(),
        Err(_) => Vec::new(),
    }
}

fn lexical_semantic_search(
    search_dir: &Path,
    query: &str,
    file_type: &str,
    limit: usize,
    min_confidence: f64,
    show_scoring: bool,
) -> Vec<SemanticHitLine> {
    let terms = tokenize_query(query);
    if terms.len() <= 1 {
        return run_single_term_search(
            search_dir,
            terms.first().map(String::as_str).unwrap_or(query),
            file_type,
            limit,
        )
        .into_iter()
        .filter(|hit| hit.confidence >= min_confidence)
        .collect();
    }

    let mut hit_counts: HashMap<String, usize> = HashMap::new();
    let mut line_content: HashMap<String, String> = HashMap::new();

    for term in &terms {
        let mut rg_args: Vec<String> = vec![
            "-n".into(),
            "--no-heading".into(),
            "--smart-case".into(),
        ];
        if !file_type.is_empty() {
            rg_args.push("--type".into());
            rg_args.push(file_type.to_string());
        }
        rg_args.push(term.clone());

        let rg_refs: Vec<&str> = rg_args.iter().map(|s| s.as_str()).collect();
        let output = crate::search_tools::run_rg(search_dir, &rg_refs);

        if let Ok(stdout) = output {
            for line in stdout.lines().take(500) {
                if let Some(key) = extract_file_line_key(line) {
                    *hit_counts.entry(key.clone()).or_insert(0) += 1;
                    line_content.entry(key).or_insert_with(|| line.to_string());
                }
            }
        }
    }

    let total_terms = terms.len().max(1);
    let mut scored: Vec<(String, usize)> = hit_counts.into_iter().collect();
    scored.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));

    scored
        .into_iter()
        .filter_map(|(key, score)| {
            let confidence = score as f64 / total_terms as f64;
            if confidence < min_confidence {
                return None;
            }
            let content = line_content.get(&key)?.clone();
            let rendered = if show_scoring {
                format!(
                    "[terms={}/{} conf={:.2}] {}",
                    score,
                    total_terms,
                    confidence,
                    content
                )
            } else {
                format!("[conf={:.2}] {}", confidence, content)
            };
            Some(SemanticHitLine { rendered, confidence })
        })
        .take(limit)
        .collect()
}

fn semantic_search_via_persisted_index(
    workspace: &Path,
    query: &str,
    target_directories: &[String],
    file_type: &str,
    limit: usize,
    min_confidence: f64,
    show_scoring: bool,
) -> Option<String> {
    let profile = matches!(
        std::env::var("SOLOCODE_MCP_SEMANTIC_LOAD_PROFILE").as_deref(),
        Ok("1")
    );
    let chunks = load_semantic_chunks(workspace)?;
    if chunks.is_empty() {
        return None;
    }

    let filtered_chunks = chunks
        .into_iter()
        .filter(|chunk| {
            (file_type.is_empty() || matches_semantic_file_type(&chunk.file_path, file_type))
                && (target_directories.is_empty()
                    || target_directories
                        .iter()
                        .any(|prefix| chunk.file_path.starts_with(prefix)))
        })
        .collect::<Vec<_>>();
    if filtered_chunks.is_empty() {
        return Some("No results.".to_string());
    }

    let t_snap = Instant::now();
    let snapshot = build_semantic_snapshot(&filtered_chunks);
    if profile {
        eprintln!(
            "[mcp-semantic] build_semantic_snapshot {:.2}ms ({} filtered chunks)",
            t_snap.elapsed().as_secs_f64() * 1000.0,
            filtered_chunks.len()
        );
    }
    let payload = RustCoreSearchRequestPayload {
        query: RustCoreSearchQueryPayload {
            query: query.to_string(),
            target_directories: target_directories.to_vec(),
            num_results: limit.max(1),
        },
        snapshot,
    };
    let raw = serde_json::to_string(&payload).ok()?;
    let response = solocode_rust_core::scoring::handle_search_request(&raw).ok()?;
    if response.hits.is_empty() {
        return Some("No results.".to_string());
    }

    let max_score = response
        .hits
        .first()
        .map(|hit| hit.score.max(0.000_001))
        .unwrap_or(1.0);
    let by_id = filtered_chunks
        .into_iter()
        .map(|chunk| (chunk.id.clone(), chunk))
        .collect::<HashMap<_, _>>();

    let rendered = response
        .hits
        .into_iter()
        .filter_map(|hit| {
            let chunk = by_id.get(&hit.chunk_id)?;
            let confidence = (hit.score / max_score).clamp(0.0, 1.0);
            if confidence < min_confidence {
                return None;
            }
            let line_range = if chunk.start_line == chunk.end_line {
                format!(":{}", chunk.start_line)
            } else {
                format!(":{}-{}", chunk.start_line, chunk.end_line)
            };
            let scope = if chunk.scope.is_empty() {
                String::new()
            } else {
                format!(" [{}]", chunk.scope)
            };
            let snippet = chunk.content.lines().next().unwrap_or_default().trim();
            let rendered = if show_scoring {
                format!(
                    "{}{}{} (score: {:.3}, conf: {:.2}, lang: {})\n   {}",
                    chunk.file_path,
                    line_range,
                    scope,
                    hit.score,
                    confidence,
                    chunk.language,
                    snippet
                )
            } else {
                format!(
                    "{}{}{} (conf: {:.2})\n   {}",
                    chunk.file_path,
                    line_range,
                    scope,
                    confidence,
                    snippet
                )
            };
            Some(rendered)
        })
        .collect::<Vec<_>>();

    Some(if rendered.is_empty() {
        "No results.".to_string()
    } else {
        rendered.join("\n")
    })
}

fn target_directories_for_search(arguments: &BTreeMap<String, Value>, path_scope: &str) -> Vec<String> {
    let raw = [
        crate::search_tools::string_arg(arguments, "target_directories"),
        crate::search_tools::string_arg(arguments, "targetDirectories"),
        crate::search_tools::string_arg(arguments, "pathScope"),
        crate::search_tools::string_arg(arguments, "path"),
    ]
    .into_iter()
    .find(|value| !value.is_empty())
    .unwrap_or_else(|| path_scope.to_string());

    raw.split(',')
        .map(|segment| segment.trim().trim_matches('/'))
        .filter(|segment| !segment.is_empty() && *segment != ".")
        .map(|segment| format!("{segment}/"))
        .collect()
}

fn load_semantic_chunks_from_disk(cache_path: &Path) -> Option<Vec<PersistedSemanticChunk>> {
    let content = fs::read_to_string(cache_path).ok()?;
    let mut chunks = Vec::new();
    for line in content.lines().filter(|line| !line.trim().is_empty()) {
        let chunk = serde_json::from_str::<PersistedSemanticChunk>(line).ok()?;
        chunks.push(chunk);
    }
    Some(chunks)
}

fn load_semantic_chunks(workspace: &Path) -> Option<Vec<PersistedSemanticChunk>> {
    let cache_path = crate::mcp_index_cache::semantic_jsonl_cache_path(workspace)?;
    let meta = fs::metadata(&cache_path).ok()?;
    let mtime = meta.modified().ok()?;
    let len = meta.len();
    let profile = matches!(
        std::env::var("SOLOCODE_MCP_SEMANTIC_LOAD_PROFILE").as_deref(),
        Ok("1")
    );
    let t0 = Instant::now();
    let mut cache_miss = false;

    let arc_chunks: Arc<Vec<PersistedSemanticChunk>> = if let Ok(mut guard) =
        PARSED_SEMANTIC_CHUNKS_CACHE.lock()
    {
        let hit = guard.as_ref().is_some_and(|c| {
            c.cache_path == cache_path && c.mtime == mtime && c.len == len
        });
        if hit {
            Arc::clone(&guard.as_ref().expect("hit implies some").chunks)
        } else {
            cache_miss = true;
            let chunks = load_semantic_chunks_from_disk(&cache_path)?;
            let arc = Arc::new(chunks);
            *guard = Some(ParsedSemanticChunksCache {
                cache_path: cache_path.clone(),
                mtime,
                len,
                chunks: Arc::clone(&arc),
            });
            arc
        }
    } else {
        cache_miss = true;
        Arc::new(load_semantic_chunks_from_disk(&cache_path)?)
    };

    if profile {
        eprintln!(
            "[mcp-semantic] jsonl {} {:.2}ms {:?}",
            if cache_miss { "MISS" } else { "HIT" },
            t0.elapsed().as_secs_f64() * 1000.0,
            cache_path
        );
    }

    Some((*arc_chunks).clone())
}

fn build_semantic_snapshot(chunks: &[PersistedSemanticChunk]) -> RustCoreSearchSnapshotPayload {
    let mut inverted_index: HashMap<String, Vec<String>> = HashMap::new();
    let mut term_frequencies: HashMap<String, HashMap<String, i32>> = HashMap::new();
    let mut doc_lengths: HashMap<String, i32> = HashMap::new();
    let mut total_doc_length = 0_f64;

    let payload_chunks = chunks
        .iter()
        .map(|chunk| {
            let contextualized_text = contextualized_text(chunk);
            let tokens = solocode_rust_core::tokenize::tokenize_query(&contextualized_text);
            let mut frequencies: HashMap<String, i32> = HashMap::new();
            for token in tokens {
                *frequencies.entry(token).or_insert(0) += 1;
            }

            let doc_len = frequencies.values().copied().sum::<i32>().max(1);
            total_doc_length += f64::from(doc_len);
            doc_lengths.insert(chunk.id.clone(), doc_len);
            term_frequencies.insert(chunk.id.clone(), frequencies.clone());
            for token in frequencies.keys() {
                inverted_index
                    .entry(token.clone())
                    .or_default()
                    .push(chunk.id.clone());
            }

            RustCoreChunkPayload {
                chunk_id: chunk.id.clone(),
                file_path: chunk.file_path.clone(),
                scope: chunk.scope.clone(),
                kind: chunk.kind.clone(),
                content: chunk.content.clone(),
                symbol_names: chunk.symbol_names.clone(),
                contextualized_text,
            }
        })
        .collect::<Vec<_>>();

    RustCoreSearchSnapshotPayload {
        chunks: payload_chunks,
        inverted_index,
        term_frequencies,
        doc_lengths,
        avg_doc_length: if chunks.is_empty() {
            0.0
        } else {
            total_doc_length / chunks.len() as f64
        },
        total_docs: chunks.len(),
        k1: 1.2,
        b: 0.75,
    }
}

fn contextualized_text(chunk: &PersistedSemanticChunk) -> String {
    let mut parts = vec![format!("# {}", chunk.file_path)];
    if !chunk.scope.is_empty() {
        parts.push(format!("# Scope: {}", chunk.scope));
    }
    if !chunk.symbol_names.is_empty() {
        parts.push(format!("# Defines: {}", chunk.symbol_names.join(", ")));
    }
    if !chunk.imports.is_empty() {
        parts.push(format!(
            "# Uses: {}",
            chunk.imports.iter().take(5).cloned().collect::<Vec<_>>().join(", ")
        ));
    }
    parts.push(chunk.content.clone());
    parts.join("\n")
}

fn matches_semantic_file_type(path: &str, file_type: &str) -> bool {
    let ext = Path::new(path)
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or("")
        .to_lowercase();
    match file_type.to_lowercase().as_str() {
        "swift" => ext == "swift",
        "rust" | "rs" => ext == "rs",
        "typescript" | "ts" => ext == "ts" || ext == "tsx" || ext == "mts" || ext == "cts",
        "javascript" | "js" => ext == "js" || ext == "jsx" || ext == "mjs" || ext == "cjs",
        "python" | "py" => ext == "py" || ext == "pyi" || ext == "pyw",
        "go" => ext == "go",
        "java" => ext == "java",
        other => ext == other,
    }
}

/// Extract "file:line" key from a ripgrep output line (format: "file:line:content").
fn extract_file_line_key(line: &str) -> Option<String> {
    let mut colons = 0;
    for (i, ch) in line.char_indices() {
        if ch == ':' {
            colons += 1;
            if colons == 2 {
                return Some(line[..i].to_string());
            }
        }
    }
    None
}

/// Tokenize a natural-language query into search terms, filtering stop words.
fn tokenize_query(query: &str) -> Vec<String> {
    static STOP_WORDS: &[&str] = &[
        "the", "a", "an", "is", "are", "was", "were", "in", "on", "at", "to",
        "for", "of", "with", "by", "from", "and", "or", "not", "this", "that",
        "it", "how", "what", "where", "when", "why", "does", "do", "if", "else",
        "i", "me", "my", "we", "our", "you", "your", "he", "she", "they",
        "be", "been", "being", "have", "has", "had", "can", "could", "will",
        "would", "should", "shall", "may", "might", "must",
    ];
    query
        .split_whitespace()
        .map(|w| w.trim_matches(|c: char| !c.is_alphanumeric() && c != '_').to_lowercase())
        .filter(|w| w.len() >= 2 && !STOP_WORDS.contains(&w.as_str()))
        .collect()
}

fn resolved_path_scope_for_search(arguments: &BTreeMap<String, Value>) -> String {
    for key in [
        "target_directories",
        "targetDirectories",
        "pathScope",
        "path",
    ] {
        let value = crate::search_tools::string_arg(arguments, key);
        if !value.is_empty() {
            return value;
        }
    }
    String::new()
}

fn shell_text(command: &str, args: &[&str], cwd: &Path) -> CallToolResult {
    // Wrap in `timeout` (coreutils / macOS gtimeout fallback) to prevent hangs.
    let timeout_cmd = if Command::new("timeout").arg("--version").output().is_ok() {
        "timeout"
    } else {
        // macOS: try gtimeout from coreutils, otherwise run without timeout.
        "gtimeout"
    };
    let has_timeout = Command::new(timeout_cmd).arg("--version").output().is_ok();

    let output = if has_timeout {
        let mut full_args = vec!["120", command];
        full_args.extend(args.iter());
        Command::new(timeout_cmd)
            .args(&full_args)
            .current_dir(cwd)
            .output()
    } else {
        // Fallback: native Rust timeout via child.wait_with_output + thread.
        run_with_native_timeout(command, args, cwd, 120)
    };

    match output {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            // Exit code 124 = timeout killed the process.
            if output.status.code() == Some(124) {
                return CallToolResult::error(format!("{command} timed out after 120s"));
            }
            if output.status.success() || output.status.code() == Some(1) {
                let text = if stdout.is_empty() { stderr } else { stdout };
                if text.is_empty() {
                    CallToolResult::text("No results.")
                } else {
                    CallToolResult::text(text)
                }
            } else {
                CallToolResult::error(if stderr.is_empty() { stdout } else { stderr })
            }
        }
        Err(error) => CallToolResult::error(error.to_string()),
    }
}

/// Native Rust timeout: spawn child, wait on a thread, kill if exceeded.
fn run_with_native_timeout(
    command: &str,
    args: &[&str],
    cwd: &Path,
    timeout_secs: u64,
) -> std::io::Result<Output> {
    let mut child = Command::new(command)
        .args(args)
        .current_dir(cwd)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;

    let timeout = std::time::Duration::from_secs(timeout_secs);
    let start = std::time::Instant::now();

    loop {
        match child.try_wait() {
            Ok(Some(_status)) => return child.wait_with_output(),
            Ok(None) => {
                if start.elapsed() >= timeout {
                    // Kill and synthesize exit code 124 (same as coreutils timeout).
                    let _ = child.kill();
                    let _ = child.wait();
                    return Ok(Output {
                        status: std::process::ExitStatus::from_raw(124 << 8),
                        stdout: Vec::new(),
                        stderr: format!("{command} timed out after {timeout_secs}s")
                            .into_bytes(),
                    });
                }
                std::thread::sleep(std::time::Duration::from_millis(200));
            }
            Err(e) => return Err(e),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokenize_query_filters_stop_words() {
        let terms = tokenize_query("how to find the auth handler in swift");
        assert!(!terms.contains(&"how".to_string()));
        assert!(!terms.contains(&"to".to_string()));
        assert!(!terms.contains(&"the".to_string()));
        assert!(!terms.contains(&"in".to_string()));
        assert!(terms.contains(&"find".to_string()));
        assert!(terms.contains(&"auth".to_string()));
        assert!(terms.contains(&"handler".to_string()));
        assert!(terms.contains(&"swift".to_string()));
    }

    #[test]
    fn tokenize_query_removes_short_and_stop_terms() {
        let terms = tokenize_query("a I me we it");
        assert!(terms.is_empty());
    }

    #[test]
    fn tokenize_query_handles_punctuation() {
        let terms = tokenize_query("find (auth_handler) in [swift]!");
        assert!(terms.contains(&"find".to_string()));
        assert!(terms.contains(&"auth_handler".to_string()));
        assert!(terms.contains(&"swift".to_string()));
    }

    #[test]
    fn tokenize_query_lowercases_terms() {
        let terms = tokenize_query("SemanticIndex BM25");
        assert!(terms.contains(&"semanticindex".to_string()));
        assert!(terms.contains(&"bm25".to_string()));
    }

    #[test]
    fn extract_file_line_key_parses_rg_output() {
        assert_eq!(
            extract_file_line_key("src/main.rs:42:fn main() {"),
            Some("src/main.rs:42".to_string())
        );
    }

    #[test]
    fn extract_file_line_key_handles_nested_paths() {
        assert_eq!(
            extract_file_line_key("Engine/CoderEngine/Sources/Foo.swift:123:let x = 1"),
            Some("Engine/CoderEngine/Sources/Foo.swift:123".to_string())
        );
    }

    #[test]
    fn extract_file_line_key_returns_none_for_invalid() {
        assert_eq!(extract_file_line_key("no colons here"), None);
        assert_eq!(extract_file_line_key("only:one"), None);
    }

    #[test]
    fn extract_file_line_key_empty_string() {
        assert_eq!(extract_file_line_key(""), None);
    }
}
