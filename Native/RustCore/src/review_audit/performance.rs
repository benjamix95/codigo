//! Performance audit tools — static analysis for bottlenecks, memory, UI responsiveness,
//! startup time, and hot paths.
//!
//! Multi-language support: Swift, Rust, TypeScript/JavaScript, Python, Go.
//! Context-aware scoring: test/mock files receive reduced severity.

use super::helpers::{detect_language, is_test_or_mock_file, pack_payload, read_file_lines, Lang};
use serde_json::{json, Value};

/// A performance pattern with optional language filter.
struct PerfPattern {
    lang: Option<Lang>,
    needle: &'static str,
    severity: &'static str,
    message: &'static str,
    remediation: &'static str,
    confidence: f64,
}

/// Downgrade severity for test/mock files.
fn effective_severity(base: &str, is_test: bool) -> &str {
    if !is_test {
        return base;
    }
    match base {
        "critical" => "suggestion",
        "warning" => "suggestion",
        _ => base,
    }
}

/// Core runner: scans files for patterns, filters by language, applies context scoring.
fn run_multilang_perf_tool(
    tool_name: &str,
    scope_files: Vec<String>,
    workspace_path: &str,
    patterns: &[PerfPattern],
) -> Result<Value, String> {
    let mut findings: Vec<Value> = Vec::new();

    for file in &scope_files {
        let lines = match read_file_lines(file, workspace_path) {
            Some(l) => l,
            None => continue,
        };
        let lang = detect_language(file);
        let test_file = is_test_or_mock_file(file);

        for (idx, line) in lines.iter().enumerate() {
            let lower = line.to_lowercase();
            for pat in patterns {
                if let Some(ref pat_lang) = pat.lang {
                    if *pat_lang != lang {
                        continue;
                    }
                }
                if lower.contains(&pat.needle.to_lowercase()) {
                    let sev = effective_severity(pat.severity, test_file);
                    let conf = if test_file {
                        (pat.confidence * 0.5).min(0.50)
                    } else {
                        pat.confidence
                    };
                    findings.push(json!({
                        "id": format!("{}-{}:{}", tool_name, file, idx + 1),
                        "severity": sev,
                        "category": "performance",
                        "origin": "audit_tool",
                        "filePath": file,
                        "lineNumber": idx + 1,
                        "message": pat.message,
                        "suggestedFix": pat.remediation,
                        "confidence": conf,
                        "evidence": line.trim(),
                        "sourceTool": tool_name,
                        "language": format!("{:?}", lang),
                        "isTestFile": test_file,
                        "blocking": sev == "critical",
                        "status": "open"
                    }));
                }
            }
        }
    }

    let summary = if findings.is_empty() {
        format!("{}: nessun problema rilevato.", tool_name)
    } else {
        format!("{}: {} finding(s).", tool_name, findings.len())
    };
    Ok(pack_payload(
        tool_name,
        findings,
        true,
        summary,
        json!({"signal_type":"pattern","multi_language":true,"context_aware":true}),
        vec![],
        vec![],
    ))
}

// ---------------------------------------------------------------------------
// Tool: bottlenecks
// ---------------------------------------------------------------------------

pub(crate) fn run_perf_bottlenecks(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let patterns = vec![
        // Swift
        PerfPattern { lang: Some(Lang::Swift), needle: "dispatchqueue.main.sync", severity: "critical", message: "Sync call on main queue — potential deadlock or UI freeze.", remediation: "Use DispatchQueue.main.async or move work off the main thread.", confidence: 0.93 },
        PerfPattern { lang: Some(Lang::Swift), needle: "thread.sleep", severity: "warning", message: "Thread.sleep blocks the current thread.", remediation: "Use Task.sleep or async timers.", confidence: 0.85 },
        PerfPattern { lang: Some(Lang::Swift), needle: "usleep(", severity: "warning", message: "usleep blocks the current thread.", remediation: "Replace with async sleep.", confidence: 0.82 },
        // Rust
        PerfPattern { lang: Some(Lang::Rust), needle: "std::thread::sleep", severity: "warning", message: "thread::sleep blocks the current thread in async context.", remediation: "Use tokio::time::sleep or async_std equivalent.", confidence: 0.85 },
        PerfPattern { lang: Some(Lang::Rust), needle: ".lock().unwrap()", severity: "warning", message: "Mutex lock with unwrap — blocks thread and panics on poison.", remediation: "Consider try_lock or handle the poison error.", confidence: 0.78 },
        PerfPattern { lang: Some(Lang::Rust), needle: ".clone()", severity: "suggestion", message: "Clone in potential hot path — may cause unnecessary allocation.", remediation: "Use references or Cow<> where possible.", confidence: 0.45 },
        // TypeScript/JavaScript
        PerfPattern { lang: Some(Lang::TypeScript), needle: "json.parse(", severity: "suggestion", message: "JSON.parse in potential hot path — CPU-intensive for large payloads.", remediation: "Consider streaming parsers or move to a worker thread.", confidence: 0.60 },
        PerfPattern { lang: Some(Lang::TypeScript), needle: "settimeout(", severity: "suggestion", message: "setTimeout used for synchronization — unreliable timing.", remediation: "Use Promises, async/await, or proper event-driven patterns.", confidence: 0.50 },
        PerfPattern { lang: Some(Lang::TypeScript), needle: "document.queryselectorall", severity: "suggestion", message: "querySelectorAll scans the entire DOM — expensive in hot paths.", remediation: "Cache selectors or use targeted lookups.", confidence: 0.55 },
        // Python
        PerfPattern { lang: Some(Lang::Python), needle: "time.sleep(", severity: "warning", message: "time.sleep blocks the event loop in async code.", remediation: "Use asyncio.sleep in async contexts.", confidence: 0.82 },
        PerfPattern { lang: Some(Lang::Python), needle: "global ", severity: "suggestion", message: "Global variable usage — potential contention in multi-threaded code.", remediation: "Use thread-local storage or pass state explicitly.", confidence: 0.50 },
        // Go
        PerfPattern { lang: Some(Lang::Go), needle: "sync.mutex", severity: "suggestion", message: "Mutex detected — review for contention in hot paths.", remediation: "Consider sync.RWMutex or atomic operations for read-heavy workloads.", confidence: 0.55 },
        PerfPattern { lang: Some(Lang::Go), needle: "time.sleep(", severity: "warning", message: "time.Sleep blocks the goroutine.", remediation: "Use context.WithTimeout or time.After for cancellable waits.", confidence: 0.78 },
        // Universal
        PerfPattern { lang: None, needle: "todo:", severity: "suggestion", message: "TODO marker — may indicate incomplete optimization.", remediation: "Review and resolve before release.", confidence: 0.30 },
    ];
    run_multilang_perf_tool("audit_perf_bottlenecks", scope_files, workspace_path, &patterns)
}

// ---------------------------------------------------------------------------
// Tool: memory
// ---------------------------------------------------------------------------

pub(crate) fn run_perf_memory(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let patterns = vec![
        // Swift
        PerfPattern { lang: Some(Lang::Swift), needle: "strong self", severity: "warning", message: "Strong self capture in closure — retain cycle risk.", remediation: "Use [weak self] or [unowned self].", confidence: 0.78 },
        PerfPattern { lang: Some(Lang::Swift), needle: "[unowned self]", severity: "suggestion", message: "unowned self can crash if self is already deallocated.", remediation: "Prefer [weak self] unless lifetime is guaranteed.", confidence: 0.65 },
        PerfPattern { lang: Some(Lang::Swift), needle: "imagenamed", severity: "suggestion", message: "UIImage(named:) caches aggressively.", remediation: "Use UIImage(contentsOfFile:) for large/temporary images.", confidence: 0.60 },
        // Rust
        PerfPattern { lang: Some(Lang::Rust), needle: "box::leak", severity: "warning", message: "Box::leak creates intentional memory leak.", remediation: "Ensure this is intentional; prefer Arc or static references.", confidence: 0.85 },
        PerfPattern { lang: Some(Lang::Rust), needle: "mem::forget", severity: "warning", message: "mem::forget prevents destructor from running.", remediation: "Use ManuallyDrop if the intent is explicit ownership transfer.", confidence: 0.82 },
        // TypeScript/JavaScript
        PerfPattern { lang: Some(Lang::TypeScript), needle: "addeventlistener(", severity: "suggestion", message: "Event listener — ensure removal to prevent memory leaks.", remediation: "Use AbortController or removeEventListener in cleanup.", confidence: 0.50 },
        PerfPattern { lang: Some(Lang::TypeScript), needle: "setinterval(", severity: "warning", message: "setInterval without clearInterval — potential memory leak.", remediation: "Store the interval ID and clearInterval in cleanup.", confidence: 0.72 },
        // Python
        PerfPattern { lang: Some(Lang::Python), needle: "__del__", severity: "suggestion", message: "__del__ finalizer complicates garbage collection.", remediation: "Use context managers or weakref for cleanup.", confidence: 0.60 },
        PerfPattern { lang: Some(Lang::Python), needle: "lru_cache", severity: "suggestion", message: "lru_cache with unbounded maxsize can grow indefinitely.", remediation: "Set an explicit maxsize parameter.", confidence: 0.55 },
        // Go
        PerfPattern { lang: Some(Lang::Go), needle: "runtime.setfinalizer", severity: "suggestion", message: "SetFinalizer complicates GC and delays collection.", remediation: "Prefer explicit Close/Release patterns.", confidence: 0.60 },
        PerfPattern { lang: Some(Lang::Go), needle: "make([]", severity: "suggestion", message: "Slice allocation — pre-size with capacity when length is known.", remediation: "Use make([]T, 0, expectedCap) to reduce reallocations.", confidence: 0.40 },
    ];
    run_multilang_perf_tool("audit_perf_memory", scope_files, workspace_path, &patterns)
}

// ---------------------------------------------------------------------------
// Tool: UI responsiveness
// ---------------------------------------------------------------------------

pub(crate) fn run_perf_ui_responsiveness(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let patterns = vec![
        // Swift
        PerfPattern { lang: Some(Lang::Swift), needle: "dispatchqueue.main.sync", severity: "critical", message: "Sync on main thread — blocks UI until completion.", remediation: "Use async dispatch or move to background.", confidence: 0.93 },
        PerfPattern { lang: Some(Lang::Swift), needle: "jsondecoder().decode", severity: "suggestion", message: "JSON decode potentially on main thread.", remediation: "Decode on a background queue.", confidence: 0.60 },
        PerfPattern { lang: Some(Lang::Swift), needle: "filemanager.default", severity: "suggestion", message: "FileManager I/O on main thread causes UI jank.", remediation: "Move I/O operations to background queue.", confidence: 0.55 },
        // TypeScript/JavaScript
        PerfPattern { lang: Some(Lang::TypeScript), needle: "document.write(", severity: "critical", message: "document.write blocks parsing and layout.", remediation: "Use DOM APIs (createElement, appendChild).", confidence: 0.90 },
        PerfPattern { lang: Some(Lang::TypeScript), needle: "innerhtml", severity: "warning", message: "innerHTML triggers full subtree re-parse and layout.", remediation: "Use textContent for text or DOM APIs for structure.", confidence: 0.65 },
        PerfPattern { lang: Some(Lang::TypeScript), needle: "alert(", severity: "warning", message: "alert() blocks the main thread and UI.", remediation: "Use non-blocking notification UI.", confidence: 0.80 },
        // Python (GUI)
        PerfPattern { lang: Some(Lang::Python), needle: "mainloop(", severity: "suggestion", message: "Tkinter/GUI mainloop — ensure long tasks run in threads.", remediation: "Use threading or asyncio for background work.", confidence: 0.50 },
    ];
    run_multilang_perf_tool("audit_perf_ui_responsiveness", scope_files, workspace_path, &patterns)
}

// ---------------------------------------------------------------------------
// Tool: startup time
// ---------------------------------------------------------------------------

pub(crate) fn run_perf_startup(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let patterns = vec![
        // Swift/ObjC
        PerfPattern { lang: Some(Lang::Swift), needle: "+load", severity: "warning", message: "+load runs before main() — slows startup.", remediation: "Move to +initialize or lazy init.", confidence: 0.88 },
        PerfPattern { lang: Some(Lang::Swift), needle: "__attribute__((constructor))", severity: "warning", message: "Constructor function runs before main().", remediation: "Defer initialization to first use.", confidence: 0.85 },
        // Rust
        PerfPattern { lang: Some(Lang::Rust), needle: "lazy_static!", severity: "suggestion", message: "lazy_static initialization on first access may cause latency spike.", remediation: "Consider std::sync::OnceLock or pre-warm in main().", confidence: 0.50 },
        PerfPattern { lang: Some(Lang::Rust), needle: "#[ctor]", severity: "warning", message: "#[ctor] runs before main — affects startup time.", remediation: "Defer to lazy initialization.", confidence: 0.82 },
        // TypeScript/JavaScript
        PerfPattern { lang: Some(Lang::TypeScript), needle: "require(", severity: "suggestion", message: "Synchronous require at module level — blocks startup.", remediation: "Use dynamic import() for non-critical modules.", confidence: 0.55 },
        // Python
        PerfPattern { lang: Some(Lang::Python), needle: "import ", severity: "suggestion", message: "Top-level import may slow startup for heavy modules.", remediation: "Use lazy imports for heavy dependencies (importlib).", confidence: 0.35 },
        // Go
        PerfPattern { lang: Some(Lang::Go), needle: "func init()", severity: "warning", message: "init() runs before main — impacts startup time.", remediation: "Move initialization to explicit setup functions.", confidence: 0.78 },
    ];
    run_multilang_perf_tool("audit_perf_startup", scope_files, workspace_path, &patterns)
}

// ---------------------------------------------------------------------------
// Tool: hot paths (nested loops + large files — language-aware)
// ---------------------------------------------------------------------------

pub(crate) fn run_perf_hot_paths(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let mut findings: Vec<Value> = Vec::new();

    for file in &scope_files {
        let lines = match read_file_lines(file, workspace_path) {
            Some(l) => l,
            None => continue,
        };
        let lang = detect_language(file);
        let test_file = is_test_or_mock_file(file);

        // Detect nested loops (universal)
        let mut nesting: usize = 0;
        for (i, line) in lines.iter().enumerate() {
            let trimmed = line.trim();
            let is_loop = match lang {
                Lang::Go => trimmed.starts_with("for "),
                Lang::Python => trimmed.starts_with("for ") || trimmed.starts_with("while "),
                _ => trimmed.starts_with("for ") || trimmed.starts_with("while ") || trimmed.starts_with("loop "),
            };
            if is_loop {
                nesting += 1;
                if nesting >= 2 {
                    let sev = effective_severity("warning", test_file);
                    findings.push(json!({
                        "id": format!("perf-hot-{}-{}", file, i + 1),
                        "severity": sev,
                        "category": "performance",
                        "origin": "audit_tool",
                        "filePath": file,
                        "lineNumber": i + 1,
                        "message": format!("Nested loop (level {}) — O(n^{}) or higher complexity.", nesting, nesting),
                        "suggestedFix": "Consider optimized data structures or algorithmic improvements.",
                        "confidence": if test_file { 0.35 } else { 0.70 },
                        "evidence": format!("nesting={} at line {}", nesting, i + 1),
                        "sourceTool": "audit_perf_hot_paths",
                        "language": format!("{:?}", lang),
                        "isTestFile": test_file,
                        "blocking": false,
                        "status": "open"
                    }));
                }
            }
            if trimmed.contains('}') || (lang == Lang::Python && !trimmed.starts_with(' ') && !trimmed.is_empty()) {
                nesting = nesting.saturating_sub(1);
            }
        }

        // Large file indicator
        if lines.len() > 500 && !test_file {
            findings.push(json!({
                "id": format!("perf-hot-large-{}", file),
                "severity": "suggestion",
                "category": "performance",
                "origin": "audit_tool",
                "filePath": file,
                "lineNumber": null,
                "message": format!("File with {} lines — candidate for decomposition and profiling.", lines.len()),
                "suggestedFix": "Consider splitting into smaller modules.",
                "confidence": 0.55,
                "evidence": format!("lines={}", lines.len()),
                "sourceTool": "audit_perf_hot_paths",
                "language": format!("{:?}", lang),
                "isTestFile": false,
                "blocking": false,
                "status": "open"
            }));
        }
    }

    let summary = if findings.is_empty() {
        "audit_perf_hot_paths: no critical hot paths detected.".to_string()
    } else {
        format!("audit_perf_hot_paths: {} finding(s).", findings.len())
    };
    Ok(pack_payload(
        "audit_perf_hot_paths",
        findings,
        true,
        summary,
        json!({"signal_type":"structural","multi_language":true,"context_aware":true}),
        vec![],
        vec![],
    ))
}
