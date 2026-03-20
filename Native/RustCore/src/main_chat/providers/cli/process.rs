use std::collections::BTreeMap;
use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Command, Stdio};

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
    let reader = BufReader::new(stdout);
    for line_result in reader.lines() {
        if is_cancelled() {
            let _ = child.kill();
            let _ = child.wait();
            return Err("cancelled".to_string());
        }
        let line = line_result.map_err(|error| format!("failed_to_read_stdout:{error}"))?;
        on_line(&line)?;
    }
    let status = child
        .wait()
        .map_err(|error| format!("failed_to_wait_child:{error}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("process_exit_{}", status.code().unwrap_or(-1)))
    }
}
