use crate::mcp_process::McpProcess;
use crate::protocol::ServerConfig;
use std::time::{SystemTime, UNIX_EPOCH};

pub struct ManagedServer {
    pub config: ServerConfig,
    pub process_key: String,
    pub status: ServerStatus,
    pub last_error: Option<String>,
    pub last_transition_reason: Option<String>,
    pub last_used_at_ms: u128,
}

pub struct ManagedProcess {
    pub process: McpProcess,
    pub last_error: Option<String>,
    pub last_transition_reason: Option<String>,
    pub last_used_at_ms: u128,
}

#[derive(Clone, Copy)]
pub enum ServerStatus {
    Disconnected,
    Ready,
    Failed,
    Stopped,
}

impl ManagedServer {
    pub fn new(config: ServerConfig) -> Self {
        Self {
            process_key: config.process_key(),
            config,
            status: ServerStatus::Disconnected,
            last_error: None,
            last_transition_reason: None,
            last_used_at_ms: now_ms(),
        }
    }

    pub fn touch(&mut self, reason: &str) {
        self.last_transition_reason = Some(reason.to_string());
        self.last_used_at_ms = now_ms();
    }
}

impl ManagedProcess {
    pub fn new(process: McpProcess, reason: &str) -> Self {
        Self {
            process,
            last_error: None,
            last_transition_reason: Some(reason.to_string()),
            last_used_at_ms: now_ms(),
        }
    }

    pub fn touch(&mut self, reason: &str) {
        self.last_transition_reason = Some(reason.to_string());
        self.last_used_at_ms = now_ms();
    }
}

fn now_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0)
}

impl ServerStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Disconnected => "disconnected",
            Self::Ready => "ready",
            Self::Failed => "failed",
            Self::Stopped => "stopped",
        }
    }
}
