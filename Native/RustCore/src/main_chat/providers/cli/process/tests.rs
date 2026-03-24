use super::stream_process_lines;
use std::collections::BTreeMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

#[test]
fn includes_stderr_in_process_exit_errors() {
    let result = stream_process_lines(
        "/bin/sh",
        &[
            "-c".to_string(),
            "echo provider failed 1>&2; exit 7".to_string(),
        ],
        ".",
        &BTreeMap::new(),
        |_| Ok(()),
        || false,
    );

    let error = result.expect_err("expected process failure");
    assert!(error.contains("process_exit_7"));
    assert!(error.contains("stderr=provider failed"));
}

#[test]
fn cancels_silent_process_without_waiting_for_stdout() {
    let cancelled = Arc::new(AtomicBool::new(false));
    let flag = Arc::clone(&cancelled);
    thread::spawn(move || {
        thread::sleep(Duration::from_millis(100));
        flag.store(true, Ordering::SeqCst);
    });

    let started_at = Instant::now();
    let result = stream_process_lines(
        "/bin/sh",
        &["-c".to_string(), "sleep 5".to_string()],
        ".",
        &BTreeMap::new(),
        |_| Ok(()),
        || cancelled.load(Ordering::SeqCst),
    );

    assert_eq!(result.unwrap_err(), "cancelled");
    assert!(started_at.elapsed() < Duration::from_secs(2));
}
