use anyhow::{Context, Result};
use std::path::Path;

/// Attempt to extract the `CombatLedgerSettings = { … }` block from an
/// existing SavedVariables file so we can preserve it when rewriting the
/// file with fresh companion data.
///
/// Uses a brace-depth counter, which is safe for the structured output
/// WoW/AceDB writes (no `{`/`}` inside string literals in practice).
fn extract_settings_block(existing: &str) -> Option<&str> {
    let marker = "CombatLedgerSettings = ";
    let start = existing.find(marker)?;
    let rest = &existing[start..];

    let mut depth: i32 = 0;
    let mut inside = false;
    let mut end = rest.len();

    for (i, c) in rest.char_indices() {
        match c {
            '{' => { inside = true; depth += 1; }
            '}' => {
                depth -= 1;
                if inside && depth == 0 {
                    end = i + 1;
                    break;
                }
            }
            _ => {}
        }
    }

    if inside { Some(&rest[..end]) } else { None }
}

/// Write `lua_content` atomically to `dest_path`.
///
/// If an existing SavedVariables file is present we first extract any
/// `CombatLedgerSettings` block written by WoW and prepend it to the new
/// content.  This prevents WoW from seeing a nil `CombatLedgerSettings`
/// on the next `/reload`, which would otherwise reset addon preferences
/// (frame position, active tab, filter state) to defaults.
pub fn write_saved_variables(dest_path: &Path, lua_content: &str) -> Result<()> {
    // Ensure the parent SavedVariables directory exists.
    if let Some(parent) = dest_path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("Cannot create directory: {}", parent.display()))?;
    }

    // Preserve CombatLedgerSettings from the last WoW-managed save, if present.
    let preserved = std::fs::read_to_string(dest_path)
        .ok()
        .and_then(|existing| extract_settings_block(&existing).map(str::to_owned));

    let final_content = match preserved {
        Some(settings) => format!("{settings}\n\n{lua_content}"),
        None => lua_content.to_owned(),
    };

    let tmp_path = dest_path.with_extension("lua.tmp");

    std::fs::write(&tmp_path, &final_content)
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
