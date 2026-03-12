use std::fmt::{Display, Formatter};

#[derive(Debug)]
pub enum BackendError {
    InvalidRequest(String),
    NotFound(String),
    Io(String),
    Protocol(String),
}

impl BackendError {
    pub fn invalid(message: impl Into<String>) -> Self {
        Self::InvalidRequest(message.into())
    }

    pub fn not_found(message: impl Into<String>) -> Self {
        Self::NotFound(message.into())
    }

    pub fn io(message: impl Into<String>) -> Self {
        Self::Io(message.into())
    }

    pub fn protocol(message: impl Into<String>) -> Self {
        Self::Protocol(message.into())
    }
}

impl Display for BackendError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidRequest(message)
            | Self::NotFound(message)
            | Self::Io(message)
            | Self::Protocol(message) => f.write_str(message),
        }
    }
}

impl std::error::Error for BackendError {}

impl From<std::io::Error> for BackendError {
    fn from(value: std::io::Error) -> Self {
        Self::io(value.to_string())
    }
}

impl From<serde_json::Error> for BackendError {
    fn from(value: serde_json::Error) -> Self {
        Self::protocol(value.to_string())
    }
}
