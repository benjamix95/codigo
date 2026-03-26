//! Audit security: dataflow/authz e supply/pattern/segreti.

mod security_core;
mod security_supply;

pub(crate) use security_core::{run_security_authz, run_security_dataflow};
pub(crate) use security_supply::{
    run_security_dependencies, run_security_patterns, run_security_secrets,
    run_security_supply_chain,
};
