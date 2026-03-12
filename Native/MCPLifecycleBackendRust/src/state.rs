use crate::mcp_process::McpProcess;
use crate::protocol::ServerConfig;

pub struct ManagedServer {
    pub config: ServerConfig,
    pub status: ServerStatus,
    pub process: Option<McpProcess>,
    pub last_error: Option<String>,
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
            config,
            status: ServerStatus::Disconnected,
            process: None,
            last_error: None,
        }
    }
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
