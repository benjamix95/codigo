use crate::boundary::audit_request;
use app_core_protocol::app_core::{AppCoreRequest, AppCoreResponse};
use std::error::Error;
use std::fmt::{Display, Formatter};

#[derive(Debug, PartialEq, Eq)]
pub struct AppCoreError {
    message: String,
}

impl AppCoreError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl Display for AppCoreError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl Error for AppCoreError {}

pub fn dispatch(request: AppCoreRequest) -> Result<AppCoreResponse, AppCoreError> {
    match request {
        AppCoreRequest::BoundaryAudit(payload) => audit_request(payload)
            .map(AppCoreResponse::BoundaryAudit)
            .map_err(AppCoreError::new),
    }
}
