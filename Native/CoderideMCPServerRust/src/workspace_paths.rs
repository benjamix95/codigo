//! Path sandbox: tutte le operazioni file devono restare sotto il workspace canonico.

use std::path::{Component, Path, PathBuf};

/// Cammina `rel` (solo relative, niente root) a partire da `workspace_canonical` rifiutando `..` che esce.
fn relative_lexical_under(workspace_canonical: &Path, rel: &Path) -> Result<PathBuf, String> {
    let mut acc = workspace_canonical.to_path_buf();
    for comp in rel.components() {
        match comp {
            Component::Prefix(_) | Component::RootDir => {
                return Err("relative path must not contain a drive/root prefix".to_string());
            }
            Component::CurDir => {}
            Component::ParentDir => {
                acc.pop();
                if !acc.starts_with(workspace_canonical) {
                    return Err("path escapes workspace (too many ..)".to_string());
                }
            }
            Component::Normal(part) => acc.push(part),
        }
    }
    Ok(acc)
}

/// Risolve `input` rispetto a `workspace` (relativo o assoluto già dentro il workspace).
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

    let workspace_canonical = workspace.canonicalize().map_err(|_| {
        format!(
            "cannot canonicalize workspace {:?} — rejecting path for safety",
            workspace.display()
        )
    })?;

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
        } else if path.is_absolute() {
            resolved.clone()
        } else {
            relative_lexical_under(&workspace_canonical, path)?
        }
    } else if path.is_absolute() {
        resolved.clone()
    } else {
        relative_lexical_under(&workspace_canonical, path)?
    };

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

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn relative_dotdot_blocked_outside_workspace() {
        let tmp = std::env::temp_dir().join(format!("ws-sandbox-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();
        let err = resolve_within_workspace(&tmp, "a/../../..").unwrap_err();
        assert!(
            err.contains("escapes") || err.contains("too many"),
            "{err}"
        );
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn nested_new_path_under_workspace_ok() {
        let tmp = std::env::temp_dir().join(format!("ws-deep-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();
        let p = resolve_within_workspace(&tmp, "a/b/c/new.txt").unwrap();
        assert!(p.to_string_lossy().contains("a/b/c"));
        let _ = fs::remove_dir_all(&tmp);
    }
}
