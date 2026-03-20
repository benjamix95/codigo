use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

const SECRET_SCAN_PATTERN: &str = r"(AKIA[0-9A-Z]{16}|-----BEGIN PRIVATE KEY-----|password\s*=\s*[^[:space:])]+|token\s*=\s*[^[:space:])]+)";

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(2)
        .expect("repo root")
        .to_path_buf()
}

fn unique_temp_file(name: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock drift")
        .as_nanos();
    std::env::temp_dir().join(format!("{name}-{nanos}.swift"))
}

#[test]
fn security_pattern_matches_real_token_assignment() {
    let fixture = unique_temp_file("solocode-validate-token-assignment");
    fs::write(&fixture, "let token = \"secret\"\n").expect("fixture write");

    let output = Command::new("rg")
        .args(["-n", SECRET_SCAN_PATTERN])
        .arg(&fixture)
        .output()
        .expect("run rg");

    let _ = fs::remove_file(&fixture);
    assert!(
        output.status.success(),
        "expected regex to match real token assignment, stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn security_pattern_does_not_match_validator_literal_regex() {
    let validator = repo_root().join("scripts/solocode-validate");
    let output = Command::new("rg")
        .args(["-n", SECRET_SCAN_PATTERN])
        .arg(&validator)
        .output()
        .expect("run rg");

    assert!(
        !output.status.success(),
        "validator script should not match its own regex literal, stdout: {}",
        String::from_utf8_lossy(&output.stdout)
    );
}
