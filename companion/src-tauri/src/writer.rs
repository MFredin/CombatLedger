use anyhow::{Context, Result};
use std::path::Path;

/// Write `lua_content` atomically to `dest_path`.
/// We write to a temporary file next to the destination and rename it,
/// so the file is never observed in a half-written state by WoW.
pub fn write_saved_variables(dest_path: &Path, lua_content: &str) -> Result<()> {
    // Ensure the parent SavedVariables directory exists.
    if let Some(parent) = dest_path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("Cannot create directory: {}", parent.display()))?;
    }

    let tmp_path = dest_path.with_extension("lua.tmp");

    std::fs::write(&tmp_path, lua_content)
        .with_context(|| format!("Cannot write temp file: {}", tmp_path.display()))?;

    std::fs::rename(&tmp_path, dest_path)
        .with_context(|| format!("Cannot rename temp file to: {}", dest_path.display()))?;

    Ok(())
}

/// Return the approximate size (bytes) of the SavedVariables file, or 0 if absent.
pub fn saved_variables_size(dest_path: &Path) -> u64 {
    std::fs::metadata(dest_path)
        .map(|m| m.len())
        .unwrap_or(0)
}
