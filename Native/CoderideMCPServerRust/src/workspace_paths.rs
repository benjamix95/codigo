//! Path sandbox: tutte le operazioni file devono restare sotto il workspace canonico.

use std::path::{Path, PathBuf};

/// Risolve `input` rispetto a `workspace` (relativo o assoluto già dentro il workspace).
/// Per file nuovi, almeno il parent esistente deve consentire di verificare il prefisso.
pub fn resolve_within_workspace(workspace: &Path, input: &str) -> Result<PathBuf, String> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return Err("path is required".to_string());
    }
    let path = Path::new(trimmed);
    let resolved = if path.is_absolute() {
        path.to_path_buf()
    } else {
        workspace.join(path)
    };

    let check_path = if resolved.exists() {
        resolved
            .canonicalize()
            .map_err(|e| format!("cannot canonicalize {}: {e}", resolved.display()))?
    } else if let Some(parent) = resolved.parent() {
        if parent.exists() {
            let canon_parent = parent
                .canonicalize()
                .map_err(|e| format!("cannot canonicalize {}: {e}", parent.display()))?;
            canon_parent.join(
                resolved
                    .file_name()
                    .ok_or_else(|| "invalid path (no file name)".to_string())?,
            )
        } else {
            resolved.clone()
        }
    } else {
        resolved.clone()
    };

    let workspace_canonical = workspace.canonicalize().map_err(|_| {
        format!(
            "cannot canonicalize workspace {:?} — rejecting path for safety",
            workspace.display()
        )
    })?;

    if !check_path.starts_with(&workspace_canonical) {
        return Err(format!(
            "path escapes workspace (must stay under {})",
            workspace_canonical.display()
        ));
    }

    Ok(resolved)
}

/// Directory (o parent se `scope` è un file) sotto cui eseguire ricerche, con sandbox workspace.
pub fn resolve_search_directory(workspace: &Path, scope: &str) -> Result<PathBuf, String> {
    let s = scope.trim();
    if s.is_empty() {
        return Ok(workspace.to_path_buf());
    }
    let resolved = resolve_within_workspace(workspace, s)?;
    if resolved.is_file() {
        return Ok(resolved
            .parent()
            .unwrap_or(workspace)
            .to_path_buf());
    }
    Ok(resolved)
}
