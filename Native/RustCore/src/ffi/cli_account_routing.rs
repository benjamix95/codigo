use super::common::{encode_raw, with_raw_json_input};
use crate::cli_account_routing::handle_action;
use app_core_protocol::cli_account_routing::{CLIAccountRoutingRequest, CLIAccountRoutingResponse};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn cli_accounts_handle_action(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: CLIAccountRoutingRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&CLIAccountRoutingResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ));
            }
        };
        encode_raw(&handle_action(request))
    })
}
