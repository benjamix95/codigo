//! Performance audit test suite — multi-language patterns and context-aware scoring.

use super::*;
use std::time::{SystemTime, UNIX_EPOCH};

fn temp_root(label: &str) -> std::path::PathBuf {
    std::env::temp_dir().join(format!(
        "review-audit-{}-{}",
        label,
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ))
}

// ---------------------------------------------------------------------------
// Swift (original)
// ---------------------------------------------------------------------------

#[test]
fn perf_bottlenecks_detects_main_sync() {
    let root = temp_root("perf-bottleneck");
    std::fs::create_dir_all(root.join("Sources")).unwrap();
    std::fs::write(
        root.join("Sources/Service.swift"),
        "func doWork() {\n    DispatchQueue.main.sync { updateUI() }\n}\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_bottlenecks",
        vec!["Sources/Service.swift".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    assert!(!result["findings"].as_array().unwrap().is_empty());
    assert_eq!(result["toolName"].as_str(), Some("audit_perf_bottlenecks"));
}

#[test]
fn perf_memory_detects_strong_self() {
    let root = temp_root("perf-memory");
    std::fs::create_dir_all(root.join("Sources")).unwrap();
    std::fs::write(
        root.join("Sources/VM.swift"),
        "service.onComplete { [strong self] in self.update() }\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_memory",
        vec!["Sources/VM.swift".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    assert!(!result["findings"].as_array().unwrap().is_empty());
}

#[test]
fn perf_hot_paths_detects_nested_loops() {
    let root = temp_root("perf-hotpath");
    std::fs::create_dir_all(root.join("Sources")).unwrap();
    std::fs::write(
        root.join("Sources/Algo.swift"),
        "for row in matrix {\n    for element in row {\n        process(element)\n    }\n}\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_hot_paths",
        vec!["Sources/Algo.swift".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    assert!(!result["findings"].as_array().unwrap().is_empty());
}

#[test]
fn perf_startup_detects_load() {
    let root = temp_root("perf-startup");
    std::fs::create_dir_all(root.join("Sources")).unwrap();
    std::fs::write(
        root.join("Sources/AppDelegate.m"),
        "@implementation AppDelegate\n+load {\n    [self setupEarly];\n}\n@end\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_startup",
        vec!["Sources/AppDelegate.m".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    assert!(!result["findings"].as_array().unwrap().is_empty());
}

#[test]
fn perf_ui_responsiveness_detects_main_sync() {
    let root = temp_root("perf-ui");
    std::fs::create_dir_all(root.join("Sources")).unwrap();
    std::fs::write(
        root.join("Sources/View.swift"),
        "struct MyView {\n    func load() {\n        DispatchQueue.main.sync { refresh() }\n    }\n}\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_ui_responsiveness",
        vec!["Sources/View.swift".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    assert!(!result["findings"].as_array().unwrap().is_empty());
    assert_eq!(
        result["toolName"].as_str(),
        Some("audit_perf_ui_responsiveness")
    );
}

// ---------------------------------------------------------------------------
// Multi-language: Rust
// ---------------------------------------------------------------------------

#[test]
fn perf_bottlenecks_detects_rust_thread_sleep() {
    let root = temp_root("perf-rust-bottleneck");
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::write(
        root.join("src/worker.rs"),
        "fn wait() {\n    std::thread::sleep(Duration::from_secs(1));\n}\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_bottlenecks",
        vec!["src/worker.rs".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    let findings = result["findings"].as_array().unwrap();
    assert!(!findings.is_empty());
    assert_eq!(findings[0]["language"].as_str(), Some("Rust"));
}

#[test]
fn perf_memory_detects_rust_box_leak() {
    let root = temp_root("perf-rust-memory");
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::write(
        root.join("src/alloc.rs"),
        "fn leak_it() {\n    let x = Box::leak(Box::new(42));\n}\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_memory",
        vec!["src/alloc.rs".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    let findings = result["findings"].as_array().unwrap();
    assert!(!findings.is_empty());
    assert_eq!(findings[0]["language"].as_str(), Some("Rust"));
}

#[test]
fn perf_startup_detects_rust_lazy_static() {
    let root = temp_root("perf-rust-startup");
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::write(
        root.join("src/config.rs"),
        "lazy_static! {\n    static ref CONFIG: Config = load_config();\n}\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_startup",
        vec!["src/config.rs".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    let findings = result["findings"].as_array().unwrap();
    assert!(!findings.is_empty());
    assert_eq!(findings[0]["language"].as_str(), Some("Rust"));
}

// ---------------------------------------------------------------------------
// Multi-language: TypeScript / JavaScript
// ---------------------------------------------------------------------------

#[test]
fn perf_bottlenecks_detects_typescript_json_parse() {
    let root = temp_root("perf-ts-bottleneck");
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::write(
        root.join("src/parser.ts"),
        "export function parse(raw: string) {\n  return JSON.parse(raw);\n}\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_bottlenecks",
        vec!["src/parser.ts".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    let findings = result["findings"].as_array().unwrap();
    assert!(!findings.is_empty());
    assert_eq!(findings[0]["language"].as_str(), Some("TypeScript"));
}

#[test]
fn perf_memory_detects_ts_setinterval() {
    let root = temp_root("perf-ts-memory");
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::write(
        root.join("src/poller.ts"),
        "function poll() {\n  setInterval(() => fetch('/api'), 1000);\n}\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_memory",
        vec!["src/poller.ts".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    let findings = result["findings"].as_array().unwrap();
    assert!(!findings.is_empty());
    assert_eq!(findings[0]["language"].as_str(), Some("TypeScript"));
}

#[test]
fn perf_ui_detects_ts_document_write() {
    let root = temp_root("perf-ts-ui");
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::write(
        root.join("src/legacy.js"),
        "function render() {\n  document.write('<h1>Hello</h1>');\n}\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_ui_responsiveness",
        vec!["src/legacy.js".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    let findings = result["findings"].as_array().unwrap();
    assert!(!findings.is_empty());
    assert_eq!(findings[0]["language"].as_str(), Some("TypeScript"));
}

// ---------------------------------------------------------------------------
// Multi-language: Python
// ---------------------------------------------------------------------------

#[test]
fn perf_bottlenecks_detects_python_time_sleep() {
    let root = temp_root("perf-py-bottleneck");
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::write(
        root.join("src/worker.py"),
        "import time\ndef wait():\n    time.sleep(5)\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_bottlenecks",
        vec!["src/worker.py".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    let findings = result["findings"].as_array().unwrap();
    assert!(!findings.is_empty());
    assert_eq!(findings[0]["language"].as_str(), Some("Python"));
}

#[test]
fn perf_memory_detects_python_del() {
    let root = temp_root("perf-py-memory");
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::write(
        root.join("src/resource.py"),
        "class Resource:\n    def __del__(self):\n        self.close()\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_memory",
        vec!["src/resource.py".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    let findings = result["findings"].as_array().unwrap();
    assert!(!findings.is_empty());
    assert_eq!(findings[0]["language"].as_str(), Some("Python"));
}

// ---------------------------------------------------------------------------
// Multi-language: Go
// ---------------------------------------------------------------------------

#[test]
fn perf_bottlenecks_detects_go_time_sleep() {
    let root = temp_root("perf-go-bottleneck");
    std::fs::create_dir_all(root.join("pkg")).unwrap();
    std::fs::write(
        root.join("pkg/handler.go"),
        "package handler\nimport \"time\"\nfunc Wait() {\n    time.Sleep(5 * time.Second)\n}\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_bottlenecks",
        vec!["pkg/handler.go".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    let findings = result["findings"].as_array().unwrap();
    assert!(!findings.is_empty());
    assert_eq!(findings[0]["language"].as_str(), Some("Go"));
}

#[test]
fn perf_memory_detects_go_setfinalizer() {
    let root = temp_root("perf-go-memory");
    std::fs::create_dir_all(root.join("pkg")).unwrap();
    std::fs::write(
        root.join("pkg/obj.go"),
        "package obj\nimport \"runtime\"\nfunc New() *Obj {\n    o := &Obj{}\n    runtime.SetFinalizer(o, cleanup)\n    return o\n}\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_memory",
        vec!["pkg/obj.go".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    let findings = result["findings"].as_array().unwrap();
    assert!(!findings.is_empty());
    assert_eq!(findings[0]["language"].as_str(), Some("Go"));
}

// ---------------------------------------------------------------------------
// Context-aware scoring
// ---------------------------------------------------------------------------

#[test]
fn perf_test_file_gets_reduced_severity() {
    let root = temp_root("perf-ctx");
    std::fs::create_dir_all(root.join("Tests")).unwrap();
    std::fs::write(
        root.join("Tests/ServiceTests.swift"),
        "func testWork() {\n    DispatchQueue.main.sync { updateUI() }\n}\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_bottlenecks",
        vec!["Tests/ServiceTests.swift".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    let findings = result["findings"].as_array().unwrap();
    assert!(!findings.is_empty());
    assert_eq!(findings[0]["severity"].as_str(), Some("suggestion"));
    assert_eq!(findings[0]["isTestFile"].as_bool(), Some(true));
    let confidence = findings[0]["confidence"].as_f64().unwrap();
    assert!(
        confidence <= 0.50,
        "Test file confidence should be ≤0.50, got {}",
        confidence
    );
}

#[test]
fn perf_non_test_file_keeps_original_severity() {
    let root = temp_root("perf-ctx-prod");
    std::fs::create_dir_all(root.join("Sources")).unwrap();
    std::fs::write(
        root.join("Sources/Service.swift"),
        "func doWork() {\n    DispatchQueue.main.sync { updateUI() }\n}\n",
    )
    .unwrap();
    let result = run_audit(
        "audit_perf_bottlenecks",
        vec!["Sources/Service.swift".to_string()],
        root.to_str().unwrap(),
        AuditParams::default(),
    )
    .unwrap();
    let findings = result["findings"].as_array().unwrap();
    assert!(!findings.is_empty());
    assert_eq!(findings[0]["severity"].as_str(), Some("critical"));
    assert_eq!(findings[0]["isTestFile"].as_bool(), Some(false));
}

// ---------------------------------------------------------------------------
// Profile integration
// ---------------------------------------------------------------------------

#[test]
fn performance_deep_profile_runs() {
    let root = temp_root("perf-profile");
    std::fs::create_dir_all(&root).unwrap();
    std::fs::write(
        root.join("a.swift"),
        "DispatchQueue.main.sync { work() }\n",
    )
    .unwrap();
    let r = run_audit(
        "audit_run_profile",
        vec!["a.swift".to_string()],
        root.to_str().unwrap(),
        AuditParams {
            profile: Some("performance_deep".into()),
            ..Default::default()
        },
    )
    .unwrap();
    assert_eq!(r["toolName"].as_str(), Some("audit_run_profile"));
    assert!(!r["findings"].as_array().unwrap().is_empty());
}
