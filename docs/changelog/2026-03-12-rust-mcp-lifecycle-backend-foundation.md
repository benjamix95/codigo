# 2026-03-12 — Rust MCP lifecycle backend foundation

## Scope
- Added a new Rust crate under `Native/MCPLifecycleBackendRust`.
- Kept Swift untouched.
- Limited workspace wiring to `Native/Cargo.toml`.

## Added
- Persistent stdio JSON-line backend with request/response envelope:
  - request: `{"id":string,"op":string,"payload":object}`
  - response: `{"id":same,"ok":bool,"payload":object,"error":string|null}`
- Supported ops:
  - `list_servers`
  - `health`
  - `list_tools`
  - `call_tool`
  - `reconnect`
  - `restart_server`
  - `shutdown_all`
- Generic subprocess MCP lifecycle management with:
  - spawn by `ServerConfig`
  - MCP `initialize`
  - `notifications/initialized`
  - `ping`
  - `tools/list`
  - `tools/call`
- Fake MCP server binary for end-to-end Rust tests.

## Protocol notes
- `list_tools` response payload exposes `tools` with:
  - `name`
  - `description`
  - `schema`
  - `serverId`
  - `serverName`
- `call_tool` response payload exposes:
  - `serverId`
  - `serverName`
  - `content`
  - `isError`
- `health` response payload exposes:
  - `states` map `serverId -> status`

## Validation
- `cargo check --manifest-path Native/MCPLifecycleBackendRust/Cargo.toml`
- `cargo test --manifest-path Native/MCPLifecycleBackendRust/Cargo.toml`

## Notes
- `cargo fmt` could not run because `rustfmt` is not installed on the current toolchain.
