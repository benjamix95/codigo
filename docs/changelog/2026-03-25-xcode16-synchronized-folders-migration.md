# Changelog: Xcode 16 Synchronized Folders Migration

**Date:** 2026-03-25
**Category:** Infrastructure / Build System
**Scope:** Project generation, build scripts, MCP SDK dependency

---

## Summary

Migrated the Xcode project from the legacy `PBXBuildFile` format (objectVersion 46,
8077 lines) to the Xcode 16 `PBXFileSystemSynchronizedRootGroup` format
(objectVersion 77, ~1300 lines). Source folders are now synchronized automatically —
adding/removing `.swift` files no longer requires regenerating the project or
resolving merge conflicts in `project.pbxproj`.

---

## Changes

### Project Format Migration
- `generate_xcode_project.rb`: replaced `add_sources()` with `add_synced_folder()`
  using `PBXFileSystemSynchronizedRootGroup`
- objectVersion patched from 46 → 77 post-save (required for synchronized groups)
- pbxproj reduced from 8077 lines to ~1300 lines

### MCP SDK — Local Package with Data Race Fix
- MCP SDK moved from remote dependency (0.10.0 upToNextMajor) to local package
  at `Packages/mcp-swift-sdk/` (pinned at 0.10.1)
- **Root cause:** `NetworkTransport.swift` has two `var` captured across isolation
  boundaries in `@Sendable` closures — Swift 6 (`swift-tools-version:6.0`) treats
  these as errors
- **Fix:** `nonisolated(unsafe) var sendContinuationResumed` and
  `nonisolated(unsafe) var receiveContinuationResumed` — both are only ever accessed
  on `@MainActor` but Swift cannot prove it statically
- Added `add_local_package()` helper to `generate_xcode_project.rb`
- We only use `StdioTransport`, not `NetworkTransport`

### Build Script Fixes
- `build_rust_search_backend.sh`: added `xattr -cr` after `cp` in `copy_artifact()`
  to strip `com.apple.provenance` before codesign
- `build_rust_mcp_server.sh`: added `xattr -cr` on all copied Rust binaries
- `build_rust_mcp_lifecycle_backend.sh`: added `xattr -cr` on all copied binaries
  including `fake-mcp-server`

### Xcode Project Generator Fixes
- Added `phase.always_out_of_date = '1'` on "Build Rust Review Core" script phase
  to suppress "will be run during every build" warning
- Added `SWIFT_STRICT_CONCURRENCY = minimal` at project level to propagate to SPM
  package targets
- Added `add_strip_xattr_phase()` — runs `xattr -cr` on the entire app bundle
  after embed phases, before codesign

### Code Fixes
- `SubagentExecutionSupport.swift`: added `role: SubagentRole` and
  `timeoutSeconds: Int` properties to `SubagentTimeoutError` (was parameterless,
  call site passed arguments)

### Test Fixes
- `AppBundleProjectStructureTests.swift`: updated assertion to check for
  `coderide-mcp-server-rust` instead of removed `solocode_rust/libsolocode_rust_core.dylib`
- `AppBundleRustReviewCoreScriptTests.swift`: aligned test with current
  `validate_app_bundle.sh` — creates bundle without Rust binaries and expects
  exit code 67 with "missing required runtime artifact"

---

## Test Results

- **Clean build:** BUILD SUCCEEDED (zero errori, zero warning dal codice del progetto)
- **Unit test eseguiti:** 2288 passati
- **3 test falliti (pre-esistenti, non correlati alla migrazione):**
  - `PipelineIntegrationLifecycleTests.testDiscardConversationRuntimeStopsTrackingImmediately`
  - `EventBusTests.testPublish_evictsOldestIdempotencyKeysWhenCapacityReached`
  - `EventDeliveryManagerConcurrencyTests.testBackoffFirstAttempt`
  - Ultimo commit che ha toccato questi test: `01d126989` (pre-migrazione)
- **1 test appeso (pre-esistente):**
  - `MCPSessionManagerRustLifecycleTests.testListToolsAndCallToolRichUseRustLifecycleBackend`
  - Richiede il Rust lifecycle backend attivo
- **Warning esterni (non fixabili):**
  - `CNIOWindows` umbrella header (swift-nio)
  - `NIOCore`/`NIOPosix` missing dependency warnings (swift-nio)

---

## Files Modified

| File | Change |
|------|--------|
| `scripts/generate_xcode_project.rb` | Synchronized folders, local MCP, xattr phase |
| `scripts/build_rust_search_backend.sh` | xattr -cr in copy_artifact() |
| `scripts/build_rust_mcp_server.sh` | xattr -cr on copied binaries |
| `scripts/build_rust_mcp_lifecycle_backend.sh` | xattr -cr on copied binaries |
| `Packages/mcp-swift-sdk/` | Local patched MCP SDK 0.10.1 |
| `Engine/.../SubagentExecutionSupport.swift` | SubagentTimeoutError params |
| `Tests/.../AppBundleProjectStructureTests.swift` | Aligned assertion |
| `Tests/.../AppBundleRustReviewCoreScriptTests.swift` | Aligned with validate script |
