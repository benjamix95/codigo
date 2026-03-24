use crate::backend::Backend;
use crate::protocol::{RequestEnvelope, ResponseEnvelope};
use std::io::{self, BufRead, Write};

pub fn run_stdio_service() -> Result<(), String> {
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let mut backend = Backend::new();

    for line in stdin.lock().lines() {
        let line = line.map_err(|error| error.to_string())?;
        if line.trim().is_empty() {
            continue;
        }
        let response = match serde_json::from_str::<RequestEnvelope>(&line) {
            Ok(request) => backend.handle(request.id, &request.op, request.payload),
            Err(error) => {
                ResponseEnvelope::err("".to_string(), format!("invalid request: {error}"))
            }
        };
        write_line(&mut stdout, &response)?;
    }
    Ok(())
}

fn write_line(stdout: &mut io::Stdout, payload: &ResponseEnvelope) -> Result<(), String> {
    let encoded = serde_json::to_string(payload).map_err(|error| error.to_string())?;
    stdout
        .write_all(encoded.as_bytes())
        .and_then(|_| stdout.write_all(b"\n"))
        .and_then(|_| stdout.flush())
        .map_err(|error| error.to_string())
}
