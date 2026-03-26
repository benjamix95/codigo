use app_core_protocol::mcp::CallToolResult;
use regex::Regex;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn handle(
    name: &str,
    workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    match name {
        "coderide_glob" => Some(glob(workspace, arguments)),
        "coderide_grep" => Some(grep(workspace, arguments)),
        "coderide_read_range" => Some(read_range(workspace, arguments)),
        "coderide_find_files" => Some(find_files(workspace, arguments)),
        "coderide_find_symbol" => Some(find_symbol(workspace, arguments)),
        "coderide_find_references" => Some(find_references(workspace, arguments)),
        "coderide_file_outline" => Some(file_outline(workspace, arguments)),
        "coderide_codebase_search" => Some(codebase_search(workspace, arguments)),
        _ => None,
    }
}

#[cfg_attr(not(test), allow(dead_code))]
pub fn supports(name: &str) -> bool {
    matches!(
        name,
        "coderide_glob"
            | "coderide_grep"
            | "coderide_read_range"
            | "coderide_find_files"
            | "coderide_find_symbol"
            | "coderide_find_references"
            | "coderide_file_outline"
            | "coderide_codebase_search"
    )
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum SearchCaseMode {
    Sensitive,
    Insensitive,
    Smart,
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum SearchOutputMode {
    Standard,
    FilesOnly,
    Count,
}

#[derive(Clone)]
struct NativeSearchOptions {
    case_mode: SearchCaseMode,
    context_lines: usize,
    multiline: bool,
    output_mode: SearchOutputMode,
    file_type: Option<String>,
    glob_filter: Option<String>,
}

fn glob(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let pattern = string_arg(arguments, "pattern");
    if pattern.is_empty() {
        return CallToolResult::error("Error: 'pattern' parameter is required");
    }
    match run_rg(workspace, &["--files", "-g", pattern.as_str()]) {
        Ok(output) if output.is_empty() => CallToolResult::text("No matches found."),
        Ok(output) => CallToolResult::text(output),
        Err(()) => CallToolResult::error("Error: failed to execute rg"),
    }
}

fn grep(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = string_arg(arguments, "query");
    let pattern = if query.is_empty() {
        string_arg(arguments, "pattern")
    } else {
        query
    };
    if pattern.is_empty() {
        return CallToolResult::error("Error: 'query' parameter is required");
    }

    let mut rg_args: Vec<String> = vec!["-n".into(), "--no-heading".into()];

    // Case sensitivity (default: case-sensitive).
    if bool_arg(arguments, "case_sensitive") == Some(false) {
        rg_args.push("-i".into());
    }

    // Context lines around matches.
    if let Some(ctx) = int_arg(arguments, "context_lines") {
        if ctx > 0 {
            rg_args.push(format!("-C{}", ctx));
        }
    }

    // Multiline matching.
    if bool_arg(arguments, "multiline") == Some(true) {
        rg_args.push("--multiline".into());
    }

    // File type filter (e.g. "swift", "rust", "ts").
    let file_type = string_arg(arguments, "fileType");
    if !file_type.is_empty() {
        rg_args.push("--type".into());
        rg_args.push(file_type);
    }

    // Glob filter (e.g. "*.swift", "src/**/*.rs").
    let glob_filter = string_arg(arguments, "glob");
    if !glob_filter.is_empty() {
        rg_args.push("-g".into());
        rg_args.push(glob_filter);
    }

    // Output mode: "files_only" → -l, "count" → -c.
    let output_mode = string_arg(arguments, "output_mode");
    match output_mode.as_str() {
        "files_only" => { rg_args.push("-l".into()); }
        "count" => { rg_args.push("-c".into()); }
        _ => {}
    }

    rg_args.push(pattern);

    // Path scope — restrict search to a subdirectory.
    let path_scope = resolved_path_scope(arguments);
    let search_dir = if path_scope.is_empty() {
        workspace.to_path_buf()
    } else {
        workspace.join(&path_scope)
    };

    let rg_refs: Vec<&str> = rg_args.iter().map(|s| s.as_str()).collect();
    match run_rg(&search_dir, &rg_refs) {
        Ok(output) if output.is_empty() => CallToolResult::text("No matches found."),
        Ok(output) => CallToolResult::text(output),
        Err(()) => CallToolResult::error("Error: failed to execute rg"),
    }
}

fn read_range(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let path = resolve_path(workspace, string_arg(arguments, "path"));
    let start = int_arg(arguments, "start")
        .or_else(|| int_arg(arguments, "start_line"))
        .unwrap_or(1)
        .max(1) as usize;
    let end = int_arg(arguments, "end")
        .or_else(|| int_arg(arguments, "end_line"))
        .unwrap_or(0) as usize;
    let Ok(content) = fs::read_to_string(&path) else {
        return CallToolResult::error(format!("Error: unable to read '{}'", path.display()));
    };
    let lines = content.lines().collect::<Vec<_>>();
    let safe_end = if end > 0 {
        end.min(lines.len())
    } else {
        (start + 200).min(lines.len())
    };
    if start == 0 || start > safe_end || start > lines.len() {
        return CallToolResult::error("Invalid line range");
    }
    let output = lines[(start - 1)..safe_end]
        .iter()
        .enumerate()
        .map(|(offset, line)| format!("{}: {}", start + offset, line))
        .collect::<Vec<_>>()
        .join("\n");
    CallToolResult::text(output)
}

fn find_files(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = string_arg(arguments, "query");
    let pattern = if query.is_empty() {
        string_arg(arguments, "pattern")
    } else {
        query
    };
    if pattern.is_empty() {
        return CallToolResult::error("Missing 'query' argument");
    }
    let extension_filter = string_arg(arguments, "extension");
    let output = run_rg(workspace, &["--files"]);
    let Ok(output) = output else {
        return CallToolResult::error("Error: failed to enumerate files");
    };
    let mut matches = output
        .lines()
        .filter(|line| {
            extension_filter.is_empty() || line.ends_with(&format!(".{extension_filter}"))
        })
        .filter(|line| line.contains(&pattern) || glob_like_match(line, &pattern))
        .take(50)
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    matches.sort();
    if matches.is_empty() {
        CallToolResult::text(format!("No files found matching '{}'", pattern))
    } else {
        CallToolResult::text(matches.join("\n"))
    }
}

fn find_symbol(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = first_non_empty(arguments, &["query", "name"]);
    if query.is_empty() {
        return CallToolResult::error("Missing 'query' argument");
    }
    let kind = string_arg(arguments, "kind");
    let keyword_group = if kind.is_empty() {
        "class|struct|enum|protocol|func|fn|def|function|interface|trait|impl|type|typealias|actor|mod|module|namespace|extension|pub fn|pub struct|pub enum|pub trait|async def|async function"
    } else {
        kind.as_str()
    };
    let regex = format!(
        r"\b({})\s+{}\b",
        keyword_group,
        regex_escape(&query)
    );
    let Ok(output) = run_rg(workspace, &["-n", "--no-heading", "-e", &regex]) else {
        return CallToolResult::error("Error: failed to search symbols");
    };
    let lines = output.lines().take(20).collect::<Vec<_>>();
    if lines.is_empty() {
        return CallToolResult::text(format!("Symbol '{}' not found in the codebase", query));
    }
    CallToolResult::text(format!(
        "Found {} definition(s) for '{}':\n\n{}",
        lines.len(),
        query,
        lines.join("\n")
    ))
}

fn find_references(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = first_non_empty(arguments, &["query", "name"]);
    if query.is_empty() {
        return CallToolResult::error("Missing 'query' argument");
    }
    let regex = format!(r"\b{}\b", regex_escape(&query));
    let Ok(output) = run_rg(workspace, &["-n", "--no-heading", "-e", &regex]) else {
        return CallToolResult::error("Error: failed to search references");
    };
    let lines = output.lines().take(100).collect::<Vec<_>>();
    if lines.is_empty() {
        return CallToolResult::text(format!("No references found for '{}'", query));
    }
    CallToolResult::text(format!(
        "Found {} reference(s) for '{}':\n{}",
        lines.len(),
        query,
        lines.join("\n")
    ))
}

fn file_outline(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let path_arg = string_arg(arguments, "path");
    if path_arg.is_empty() {
        return CallToolResult::error("Missing 'path' argument");
    }
    let path = resolve_path(workspace, path_arg);
    let Ok(content) = fs::read_to_string(&path) else {
        return CallToolResult::error(format!("Error: unable to read '{}'", path.display()));
    };
    let keywords = outline_keywords_for_path(&path);
    let mut items = Vec::new();
    for (index, line) in content.lines().enumerate() {
        let trimmed = line.trim();
        if keywords.iter().any(|kw| trimmed.starts_with(kw)) {
            items.push(format!("{}: {}", index + 1, trimmed));
        }
    }
    if items.is_empty() {
        CallToolResult::text(format!(
            "No symbols found in '{}'. File may not be indexed.",
            path.display()
        ))
    } else {
        CallToolResult::text(items.join("\n"))
    }
}

/// Returns outline keywords based on file extension.
fn outline_keywords_for_path(path: &Path) -> Vec<&'static str> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();
    match ext.as_str() {
        "swift" => vec![
            "import ", "class ", "struct ", "enum ", "protocol ", "func ",
            "extension ", "typealias ", "actor ", "macro ",
        ],
        "rs" => vec![
            "pub fn ", "fn ", "pub struct ", "struct ", "pub enum ", "enum ",
            "impl ", "pub trait ", "trait ", "mod ", "pub mod ", "use ",
            "pub type ", "type ", "pub const ", "const ", "pub static ", "static ",
        ],
        "ts" | "tsx" | "js" | "jsx" | "mjs" => vec![
            "function ", "class ", "interface ", "type ", "enum ",
            "export ", "import ", "const ", "async function ",
        ],
        "py" => vec!["def ", "class ", "import ", "from ", "async def "],
        "go" => vec!["func ", "type ", "import ", "package ", "interface "],
        "rb" => vec!["def ", "class ", "module ", "require "],
        "java" | "kt" | "kts" => vec![
            "class ", "interface ", "enum ", "fun ", "import ", "package ",
            "public class ", "public interface ", "abstract class ",
        ],
        "c" | "cpp" | "cc" | "cxx" | "h" | "hpp" => vec![
            "#include ", "class ", "struct ", "enum ", "typedef ",
            "namespace ", "template ", "void ", "int ", "auto ",
        ],
        _ => vec![
            "class ", "struct ", "func ", "function ", "fn ", "def ",
            "import ", "enum ", "interface ", "trait ", "type ",
            "module ", "package ", "namespace ",
        ],
    }
}

/// Codebase search with multi-term scoring for natural-language queries.
/// Single-term queries use fast rg grep. Multi-term queries score results
/// by the number of distinct matching terms per file:line.
fn codebase_search(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = resolved_codebase_search_query(arguments);
    if query.is_empty() {
        return CallToolResult::error("Missing 'query' argument");
    }

    let terms = codebase_search_tokenize(&query);

    // Single term → fast path (simple grep).
    if terms.len() <= 1 {
        let search_term = if terms.is_empty() { &query } else { &terms[0] };
        let Ok(output) = run_rg(workspace, &["-n", "--no-heading", "--smart-case", "-e", search_term]) else {
            return CallToolResult::error("Error: failed to search codebase");
        };
        let lines = output.lines().take(50).collect::<Vec<_>>();
        if lines.is_empty() {
            return CallToolResult::text(format!("No symbols found matching '{}'", query));
        }
        return CallToolResult::text(lines.join("\n"));
    }

    // Multi-term → score each file:line by number of matching terms.
    let mut hit_counts: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    let mut line_content: std::collections::HashMap<String, String> = std::collections::HashMap::new();

    for term in &terms {
        let Ok(output) = run_rg(workspace, &["-n", "--no-heading", "--smart-case", "-e", term]) else {
            continue;
        };
        for line in output.lines().take(500) {
            if let Some(key) = codebase_search_file_line_key(line) {
                *hit_counts.entry(key.clone()).or_insert(0) += 1;
                line_content.entry(key).or_insert_with(|| line.to_string());
            }
        }
    }

    if hit_counts.is_empty() {
        return CallToolResult::text(format!("No symbols found matching '{}'", query));
    }

    let mut scored: Vec<(&String, &usize)> = hit_counts.iter().collect();
    scored.sort_by(|a, b| b.1.cmp(a.1).then_with(|| a.0.cmp(b.0)));

    let total_terms = terms.len();
    let results: Vec<String> = scored
        .iter()
        .take(50)
        .map(|(key, score)| {
            let content = line_content.get(*key).map(|s| s.as_str()).unwrap_or(key);
            format!("[{}/{}] {}", score, total_terms, content)
        })
        .collect();

    CallToolResult::text(results.join("\n"))
}

fn codebase_search_file_line_key(line: &str) -> Option<String> {
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

fn codebase_search_tokenize(query: &str) -> Vec<String> {
    static STOP: &[&str] = &[
        "the", "a", "an", "is", "are", "was", "were", "in", "on", "at", "to",
        "for", "of", "with", "by", "from", "and", "or", "not", "this", "that",
        "it", "how", "what", "where", "when", "why", "does", "do", "if", "else",
    ];
    query
        .split_whitespace()
        .map(|w| w.trim_matches(|c: char| !c.is_alphanumeric() && c != '_').to_lowercase())
        .filter(|w| w.len() >= 2 && !STOP.contains(&w.as_str()))
        .collect()
}

fn resolved_codebase_search_query(arguments: &BTreeMap<String, Value>) -> String {
    let direct = string_arg(arguments, "query");
    if !direct.is_empty() {
        return direct;
    }

    for key in ["path", "file", "filePattern", "pattern"] {
        let fallback = string_arg(arguments, key);
        if fallback.is_empty() {
            continue;
        }
        let candidate = Path::new(fallback.trim())
            .file_stem()
            .and_then(|value| value.to_str())
            .unwrap_or(fallback.as_str())
            .trim()
            .to_string();
        if !candidate.is_empty() {
            return candidate;
        }
    }

    String::new()
}

pub(crate) fn run_rg(workspace: &Path, args: &[&str]) -> Result<String, ()> {
    match Command::new("rg")
        .args(args)
        .current_dir(workspace)
        .output()
    {
        Ok(output) if output.status.success() || output.status.code() == Some(1) => {
            Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
        }
        Ok(_) => Err(()),
        Err(_) => run_rg_native_fallback(workspace, args),
    }
}

// ---------------------------------------------------------------------------
// Native fallback: used when `rg` binary is not available on the system.
// Supports the two main modes: file listing (--files) and text search (-e).
// ---------------------------------------------------------------------------

fn run_rg_native_fallback(workspace: &Path, args: &[&str]) -> Result<String, ()> {
    let is_files_mode = args.contains(&"--files");
    let options = native_search_options_from_args(args);
    if is_files_mode {
        let glob_pattern = args
            .windows(2)
            .find(|w| w[0] == "-g")
            .map(|w| w[1].to_string());
        Ok(native_walk_files(workspace, glob_pattern.as_deref(), &options))
    } else {
        let pattern = args
            .windows(2)
            .rev()
            .find(|w| w[0] == "-e")
            .map(|w| w[1].to_string())
            .or_else(|| {
                // Last positional arg is the pattern when no -e flag.
                args.last()
                    .filter(|a| !a.starts_with('-'))
                    .map(|s| s.to_string())
            })
            .unwrap_or_default();
        if pattern.is_empty() {
            return Err(());
        }
        Ok(native_grep(workspace, &pattern, &options))
    }
}

fn native_search_options_from_args(args: &[&str]) -> NativeSearchOptions {
    let case_mode = if args.contains(&"-i") {
        SearchCaseMode::Insensitive
    } else if args.contains(&"--smart-case") {
        SearchCaseMode::Smart
    } else {
        SearchCaseMode::Sensitive
    };
    let context_lines = args
        .iter()
        .find_map(|arg| arg.strip_prefix("-C"))
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(0);
    let file_type = args
        .windows(2)
        .find(|window| window[0] == "--type")
        .map(|window| window[1].to_string());
    let glob_filter = args
        .windows(2)
        .find(|window| window[0] == "-g")
        .map(|window| window[1].to_string());
    let output_mode = if args.contains(&"-l") {
        SearchOutputMode::FilesOnly
    } else if args.contains(&"-c") {
        SearchOutputMode::Count
    } else {
        SearchOutputMode::Standard
    };

    NativeSearchOptions {
        case_mode,
        context_lines,
        multiline: args.contains(&"--multiline"),
        output_mode,
        file_type,
        glob_filter,
    }
}

fn native_walk_files(
    dir: &Path,
    glob_pattern: Option<&str>,
    options: &NativeSearchOptions,
) -> String {
    let mut files = Vec::new();
    native_walk_recursive(dir, dir, &mut files, options);
    files.sort();
    match glob_pattern {
        Some(pattern) => files
            .into_iter()
            .filter(|f| glob_like_match(f, pattern))
            .collect::<Vec<_>>()
            .join("\n"),
        None => files.join("\n"),
    }
}

fn native_walk_recursive(
    root: &Path,
    dir: &Path,
    out: &mut Vec<String>,
    options: &NativeSearchOptions,
) {
    let Ok(entries) = fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        let file_name = entry.file_name();
        let name = file_name.to_string_lossy();
        // Skip hidden dirs and common non-source directories.
        if name.starts_with('.') || name == "node_modules" || name == "target" || name == "build" {
            continue;
        }
        if path.is_dir() {
            native_walk_recursive(root, &path, out, options);
        } else if path.is_file() {
            if let Ok(rel) = path.strip_prefix(root) {
                let rel_str = rel.to_string_lossy().to_string();
                if !matches_file_type(&rel_str, options.file_type.as_deref()) {
                    continue;
                }
                if let Some(glob_filter) = options.glob_filter.as_deref() {
                    if !glob_like_match(&rel_str, glob_filter) {
                        continue;
                    }
                }
                out.push(rel_str);
            }
        }
    }
}

fn native_grep(dir: &Path, pattern: &str, options: &NativeSearchOptions) -> String {
    let mut files = Vec::new();
    native_walk_recursive(dir, dir, &mut files, options);
    files.sort();

    // Try regex first; if invalid, fall back to literal contains.
    let regex_pattern = make_native_regex_pattern(pattern, options.case_mode);
    let re = Regex::new(&regex_pattern).ok();

    let case_insensitive = native_case_insensitive(pattern, options.case_mode);
    let literal_lower = if case_insensitive {
        Some(pattern.to_lowercase())
    } else {
        None
    };

    let mut results = Vec::new();
    let max_results = 500;
    let mut file_counts: Vec<(String, usize)> = Vec::new();
    let mut file_paths = BTreeSet::new();
    'outer: for rel_path in &files {
        let full_path = dir.join(rel_path);
        let Ok(content) = fs::read_to_string(&full_path) else { continue };
        if options.multiline {
            let file_match_count = if let Some(ref re) = re {
                re.find_iter(&content).count()
            } else if let Some(ref lower) = literal_lower {
                content.to_lowercase().matches(lower.as_str()).count()
            } else {
                content.matches(pattern).count()
            };
            if file_match_count == 0 {
                continue;
            }
            match options.output_mode {
                SearchOutputMode::FilesOnly => {
                    file_paths.insert(rel_path.clone());
                }
                SearchOutputMode::Count => {
                    file_counts.push((rel_path.clone(), file_match_count));
                }
                SearchOutputMode::Standard => {
                    let preview = content.lines().next().unwrap_or_default();
                    results.push(format!("{rel_path}:1:{preview}"));
                }
            }
            if results.len() >= max_results || file_paths.len() >= max_results {
                break;
            }
            continue;
        }

        let lines: Vec<&str> = content.lines().collect();
        let mut matched_line_indexes = Vec::new();
        for (line_num, line) in lines.iter().enumerate() {
            let matched = if let Some(ref re) = re {
                re.is_match(line)
            } else if let Some(ref lower) = literal_lower {
                line.to_lowercase().contains(lower.as_str())
            } else {
                line.contains(pattern)
            };
            if matched {
                matched_line_indexes.push(line_num);
            }
        }

        if matched_line_indexes.is_empty() {
            continue;
        }

        match options.output_mode {
            SearchOutputMode::FilesOnly => {
                file_paths.insert(rel_path.clone());
            }
            SearchOutputMode::Count => {
                file_counts.push((rel_path.clone(), matched_line_indexes.len()));
            }
            SearchOutputMode::Standard => {
                let rendered = render_context_matches(
                    rel_path,
                    &lines,
                    &matched_line_indexes,
                    options.context_lines,
                    max_results.saturating_sub(results.len()),
                );
                results.extend(rendered);
                if results.len() >= max_results {
                    break 'outer;
                }
            }
        }
    }

    match options.output_mode {
        SearchOutputMode::FilesOnly => file_paths.into_iter().collect::<Vec<_>>().join("\n"),
        SearchOutputMode::Count => file_counts
            .into_iter()
            .map(|(path, count)| format!("{path}:{count}"))
            .collect::<Vec<_>>()
            .join("\n"),
        SearchOutputMode::Standard => results.join("\n"),
    }
}

fn render_context_matches(
    rel_path: &str,
    lines: &[&str],
    matches: &[usize],
    context_lines: usize,
    remaining_budget: usize,
) -> Vec<String> {
    let mut rendered = Vec::new();
    let mut seen = BTreeSet::new();

    for &match_index in matches {
        let start = match_index.saturating_sub(context_lines);
        let end = (match_index + context_lines).min(lines.len().saturating_sub(1));
        for line_index in start..=end {
            if !seen.insert(line_index) {
                continue;
            }
            rendered.push(format!(
                "{rel_path}:{}:{}",
                line_index + 1,
                lines.get(line_index).copied().unwrap_or_default()
            ));
            if rendered.len() >= remaining_budget {
                return rendered;
            }
        }
    }

    rendered
}

fn native_case_insensitive(pattern: &str, case_mode: SearchCaseMode) -> bool {
    match case_mode {
        SearchCaseMode::Insensitive => true,
        SearchCaseMode::Sensitive => false,
        SearchCaseMode::Smart => !pattern.chars().any(|ch| ch.is_uppercase()),
    }
}

fn make_native_regex_pattern(pattern: &str, case_mode: SearchCaseMode) -> String {
    if native_case_insensitive(pattern, case_mode) {
        format!("(?i){pattern}")
    } else {
        pattern.to_string()
    }
}

fn matches_file_type(path: &str, file_type: Option<&str>) -> bool {
    let Some(file_type) = file_type else { return true };
    let extension = Path::new(path)
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or("")
        .to_lowercase();
    match file_type.to_lowercase().as_str() {
        "swift" => extension == "swift",
        "rust" | "rs" => extension == "rs",
        "typescript" | "ts" => extension == "ts" || extension == "tsx" || extension == "mts" || extension == "cts",
        "javascript" | "js" => extension == "js" || extension == "jsx" || extension == "mjs" || extension == "cjs",
        "python" | "py" => extension == "py" || extension == "pyi" || extension == "pyw",
        "go" => extension == "go",
        "java" => extension == "java",
        "kotlin" | "kt" => extension == "kt" || extension == "kts",
        "ruby" | "rb" => extension == "rb" || extension == "rake",
        "c" => extension == "c" || extension == "h",
        "cpp" | "c++" => {
            ["cpp", "cc", "cxx", "hpp", "hh", "hxx"].contains(&extension.as_str())
        }
        other => extension == other,
    }
}

pub(crate) fn string_arg(arguments: &BTreeMap<String, Value>, key: &str) -> String {
    arguments
        .get(key)
        .and_then(|value| match value {
            Value::String(text) => Some(text.trim().to_string()),
            Value::Number(number) => Some(number.to_string()),
            Value::Bool(flag) => Some(flag.to_string()),
            _ => None,
        })
        .unwrap_or_default()
}

fn first_non_empty(arguments: &BTreeMap<String, Value>, keys: &[&str]) -> String {
    keys.iter()
        .map(|key| string_arg(arguments, key))
        .find(|value| !value.is_empty())
        .unwrap_or_default()
}

/// Resolve path scope from multiple aliases used by different callers.
fn resolved_path_scope(arguments: &BTreeMap<String, Value>) -> String {
    for key in ["pathScope", "path", "target_directories", "targetDirectories"] {
        let value = string_arg(arguments, key);
        if !value.is_empty() {
            return value;
        }
    }
    String::new()
}

pub(crate) fn int_arg(arguments: &BTreeMap<String, Value>, key: &str) -> Option<i64> {
    arguments
        .get(key)
        .and_then(|value| value.as_i64().or_else(|| value.as_str()?.trim().parse::<i64>().ok()))
}

pub(crate) fn float_arg(arguments: &BTreeMap<String, Value>, key: &str) -> Option<f64> {
    arguments
        .get(key)
        .and_then(|value| value.as_f64().or_else(|| value.as_str()?.trim().parse::<f64>().ok()))
}

pub(crate) fn bool_arg(arguments: &BTreeMap<String, Value>, key: &str) -> Option<bool> {
    arguments.get(key).and_then(|value| {
        value.as_bool().or_else(|| {
            value.as_str().and_then(|raw| match raw.trim().to_ascii_lowercase().as_str() {
                "true" | "1" | "yes" | "on" => Some(true),
                "false" | "0" | "no" | "off" => Some(false),
                _ => None,
            })
        })
    })
}

fn resolve_path(workspace: &Path, input: String) -> PathBuf {
    let path = Path::new(input.trim());
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        workspace.join(path)
    }
}

fn regex_escape(input: &str) -> String {
    regex_chars(input)
        .chars()
        .fold(String::new(), |mut acc, ch| {
            if ".+*?^$()[]{}|\\".contains(ch) {
                acc.push('\\');
            }
            acc.push(ch);
            acc
        })
}

fn regex_chars(input: &str) -> String {
    input.trim().to_string()
}

fn glob_like_match(path: &str, pattern: &str) -> bool {
    if !pattern.contains('*') {
        return path.contains(pattern);
    }
    // Split on '*' keeping empty segments for prefix/suffix anchoring.
    let parts: Vec<&str> = pattern.split('*').collect();
    if parts.iter().all(|p| p.is_empty()) {
        return true; // pattern is all wildcards
    }
    let must_start = !pattern.starts_with('*');
    let must_end = !pattern.ends_with('*');

    let mut cursor = 0usize;
    for (index, part) in parts.iter().enumerate() {
        if part.is_empty() {
            continue;
        }
        let Some(position) = path[cursor..].find(part) else {
            return false;
        };
        if must_start && index == 0 && position != 0 {
            return false;
        }
        cursor += position + part.len();
    }
    if must_end && cursor != path.len() {
        return false;
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;
    use std::collections::BTreeMap;

    #[test]
    fn codebase_search_query_falls_back_to_path_stem() {
        let mut args = BTreeMap::new();
        args.insert(
            "path".to_string(),
            Value::String(
                "App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift"
                    .to_string(),
            ),
        );

        assert_eq!(
            resolved_codebase_search_query(&args),
            "ChatStore+RustBridge".to_string()
        );
    }

    #[test]
    fn codebase_search_tokenize_filters_stop_words() {
        let terms = codebase_search_tokenize("where is the error handling");
        assert!(!terms.contains(&"where".to_string()));
        assert!(!terms.contains(&"is".to_string()));
        assert!(!terms.contains(&"the".to_string()));
        assert!(terms.contains(&"error".to_string()));
        assert!(terms.contains(&"handling".to_string()));
    }

    #[test]
    fn codebase_search_tokenize_preserves_underscored_terms() {
        let terms = codebase_search_tokenize("find_symbol search_engine");
        assert!(terms.contains(&"find_symbol".to_string()));
        assert!(terms.contains(&"search_engine".to_string()));
    }

    #[test]
    fn codebase_search_file_line_key_parses_correctly() {
        assert_eq!(
            codebase_search_file_line_key("Engine/CoderEngine/Sources/Foo.swift:123:let x = 1"),
            Some("Engine/CoderEngine/Sources/Foo.swift:123".to_string())
        );
    }

    #[test]
    fn codebase_search_file_line_key_returns_none_for_single_colon() {
        assert_eq!(codebase_search_file_line_key("only:one"), None);
    }

    #[test]
    fn codebase_search_file_line_key_returns_none_for_empty() {
        assert_eq!(codebase_search_file_line_key(""), None);
    }
}
