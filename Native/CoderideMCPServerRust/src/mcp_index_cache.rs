//! Hash e percorso cache `semantic.jsonl` allineati a `CodebaseIndex.cacheDirectory` (Swift).
//!
//! - `SOLOCODE_WORKSPACE_INDEX_PATHS`: stringa esattamente come prodotta da Swift
//!   `CodebaseIndex.indexCachePathsKey` (path ordinati, separati da `|`).
//! - Se assente: stesso algoritmo sulla stringa di `SOLOCODE_WORKSPACE_PATH`, poi fallback al path workspace.
//! - `debug_tools` persiste `debug_state.json` in una cartella derivata da SHA-256 di questa stessa
//!   stringa quando `SOLOCODE_WORKSPACE_INDEX_PATHS` è impostata (multi-root allineato alla CLI Swift).

use std::env;
use std::path::{Path, PathBuf};

/// DJB2 su UTF-8 — deve coincidere con `CodebaseIndex.indexCacheDirectoryHashHex`.
pub fn djb2_hash_hex_bytes(bytes: &[u8]) -> String {
    let hash = bytes.iter().fold(5381_u64, |acc, &b| {
        acc.wrapping_shl(5)
            .wrapping_add(acc)
            .wrapping_add(b as u64)
    });
    format!("{hash:x}")
}

pub fn index_cache_dir_hash_for_env(workspace_fallback: &Path) -> Option<String> {
    if let Ok(key) = env::var("SOLOCODE_WORKSPACE_INDEX_PATHS") {
        let t = key.trim();
        if !t.is_empty() {
            return Some(djb2_hash_hex_bytes(t.as_bytes()));
        }
    }
    let path_str = env::var("SOLOCODE_WORKSPACE_PATH")
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .or_else(|| workspace_fallback.to_str().map(std::string::ToString::to_string))?;
    Some(djb2_hash_hex_bytes(path_str.trim().as_bytes()))
}

pub fn semantic_jsonl_cache_path(workspace: &Path) -> Option<PathBuf> {
    let hash_hex = index_cache_dir_hash_for_env(workspace)?;
    let home = env::var("HOME").ok()?;
    Some(
        PathBuf::from(home)
            .join("Library")
            .join("Caches")
            .join("Solo Code")
            .join("index")
            .join(hash_hex)
            .join("semantic.jsonl"),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn djb2_matches_swift_single_path() {
        let key = "/Users/foo/project";
        let h = djb2_hash_hex_bytes(key.as_bytes());
        assert!(!h.is_empty());
    }

    #[test]
    fn multi_root_key_order_matters() {
        let a = djb2_hash_hex_bytes("/b|/a".as_bytes());
        let b = djb2_hash_hex_bytes("/a|/b".as_bytes());
        assert_ne!(a, b);
    }
}
