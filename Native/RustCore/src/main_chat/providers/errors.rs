use std::fmt::{Display, Formatter};

#[derive(Debug, Clone)]
pub struct ProviderTransportError {
    pub message: String,
}

impl ProviderTransportError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl Display for ProviderTransportError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for ProviderTransportError {}

impl From<std::io::Error> for ProviderTransportError {
    fn from(value: std::io::Error) -> Self {
        Self::new(value.to_string())
    }
}

impl From<reqwest::Error> for ProviderTransportError {
    fn from(value: reqwest::Error) -> Self {
        Self::new(value.to_string())
    }
}

impl From<serde_json::Error> for ProviderTransportError {
    fn from(value: serde_json::Error) -> Self {
        Self::new(value.to_string())
    }
}
