use std::collections::BTreeMap;
use std::io::{BufRead, BufReader, Read};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::Duration;

pub(crate) fn stream_process_lines(
    executable: &str,
    arguments: &[String],
    working_directory: &str,
    environment: &BTreeMap<String, String>,
    mut on_line: impl FnMut(&str) -> Result<(), String>,
    is_cancelled: impl Fn() -> bool,
) -> Result<(), String> {
    let mut command = Command::new(executable);
    command.args(arguments);
    command.current_dir(Path::new(working_directory));
    command.stdin(Stdio::null());
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());
    for (key, value) in environment {
        command.env(key, value);
    }
    let mut child = command
        .spawn()
        .map_err(|error| format!("failed_to_spawn:{error}"))?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "missing_stdout_pipe".to_string())?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| "missing_stderr_pipe".to_string())?;

    let (stdout_tx, stdout_rx) = mpsc::channel();
    let stdout_thread = thread::spawn(move || {
        let reader = BufReader::new(stdout);
        for line_result in reader.lines() {
            let result = line_result.map_err(|error| format!("failed_to_read_stdout:{error}"));
            if stdout_tx.send(result).is_err() {
                break;
            }
        }
    });
    let stderr_thread = thread::spawn(move || {
        let mut output = String::new();
        let mut reader = BufReader::new(stderr);
        reader
            .read_to_string(&mut output)
            .map_err(|error| format!("failed_to_read_stderr:{error}"))?;
        Ok(output)
    });

    loop {
        if is_cancelled() {
            let _ = child.kill();
            let _ = child.wait();
            let _ = stdout_thread.join();
            let _ = finish_stderr(stderr_thread);
            return Err("cancelled".to_string());
        }
        match stdout_rx.recv_timeout(Duration::from_millis(50)) {
            Ok(Ok(line)) => on_line(&line)?,
            Ok(Err(error)) => {
                let _ = child.kill();
                let _ = child.wait();
                let _ = stdout_thread.join();
                let stderr_output = finish_stderr(stderr_thread)?;
                return Err(append_stderr_context(error, &stderr_output));
            }
            Err(RecvTimeoutError::Timeout) => {
                if let Some(status) = child
                    .try_wait()
                    .map_err(|error| format!("failed_to_wait_child:{error}"))?
                {
                    let _ = stdout_thread.join();
                    let stderr_output = finish_stderr(stderr_thread)?;
                    return exit_status_result(status.code(), &stderr_output);
                }
            }
            Err(RecvTimeoutError::Disconnected) => {
                let status = child
                    .wait()
                    .map_err(|error| format!("failed_to_wait_child:{error}"))?;
                let _ = stdout_thread.join();
                let stderr_output = finish_stderr(stderr_thread)?;
                return exit_status_result(status.code(), &stderr_output);
            }
        }
    }
}

fn finish_stderr(
    stderr_thread: thread::JoinHandle<Result<String, String>>,
) -> Result<String, String> {
    stderr_thread
        .join()
        .map_err(|_| "failed_to_join_stderr_reader".to_string())?
}

fn exit_status_result(code: Option<i32>, stderr_output: &str) -> Result<(), String> {
    if code.unwrap_or(0) == 0 {
        Ok(())
    } else {
        Err(append_stderr_context(
            format!("process_exit_{}", code.unwrap_or(-1)),
            stderr_output,
        ))
    }
}

fn append_stderr_context(base: String, stderr_output: &str) -> String {
    let trimmed = stderr_output.trim();
    if trimmed.is_empty() {
        base
    } else {
        format!("{base}:stderr={trimmed}")
    }
}

#[cfg(test)]
mod tests;
