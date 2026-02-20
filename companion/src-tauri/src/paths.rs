use anyhow::{Context, Result};
use std::path::{Path, PathBuf};

/// Resolved WoW paths needed by the companion.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct WowPaths {
    pub wow_root: PathBuf,
    pub combat_log: PathBuf,
    /// WoW's own SavedVariables file — managed by WoW, used for CombatLedgerSettings only.
    pub saved_variables: PathBuf,
    /// Addon-directory Lua file written by the companion for CombatLedgerDB.
    /// WoW loads this file on every /reload (it is listed in the .toc) but never
    /// writes to it, so companion data is never overwritten by WoW's save pass.
    pub generated_data: PathBuf,
    pub account_name: String,
}

/// Attempt to auto-detect the WoW installation root.
pub fn detect_wow_root() -> Option<PathBuf> {
    #[cfg(target_os = "windows")]
    {
        if let Some(p) = detect_wow_root_windows() {
            return Some(p);
        }
        let fallback = PathBuf::from(r"C:\Program Files (x86)\World of Warcraft\_retail_");
        if fallback.exists() {
            return Some(fallback);
        }
    }

    #[cfg(target_os = "macos")]
    {
        let macos_path = PathBuf::from("/Applications/World of Warcraft/_retail_");
        if macos_path.exists() {
            return Some(macos_path);
        }
    }

    None
}

#[cfg(target_os = "windows")]
fn detect_wow_root_windows() -> Option<PathBuf> {
    // Attempt registry lookup: HKLM\SOFTWARE\Blizzard Entertainment\World of Warcraft
    // Using the winreg crate would be cleaner, but we keep deps minimal and shell out.
    use std::process::Command;
    let output = Command::new("reg")
        .args([
            "query",
            r"HKEY_LOCAL_MACHINE\SOFTWARE\Blizzard Entertainment\World of Warcraft",
            "/v",
            "InstallPath",
        ])
        .output()
        .ok()?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        if line.contains("InstallPath") {
            let parts: Vec<&str> = line.splitn(3, "    ").collect();
            if parts.len() == 3 {
                let raw = parts[2].trim();
                let path = PathBuf::from(raw).join("_retail_");
                if path.exists() {
                    return Some(path);
                }
            }
        }
    }
    None
}

/// Discover the Battle.net account directory under WTF/Account/.
///
/// WoW places a `SavedVariables/` directory directly inside `WTF/Account/` for
/// account-wide addon data — this is NOT a Battle.net account name and must be
/// excluded.  The reliable discriminator is that every real account directory
/// contains its own `SavedVariables/` subdirectory, whereas the account-wide
/// `SavedVariables/` directory contains only `.lua` files (no subdirectory of
/// that name).  Blizzard internal directories (prefixed with `#`) are also skipped.
pub fn discover_account_names(wow_root: &Path) -> Result<Vec<String>> {
    let account_dir = wow_root.join("WTF").join("Account");
    let entries = std::fs::read_dir(&account_dir)
        .with_context(|| format!("Cannot read WTF/Account directory: {}", account_dir.display()))?;

    let mut names = Vec::new();
    for entry in entries.flatten() {
        if entry.file_type().map(|t| t.is_dir()).unwrap_or(false) {
            if let Some(name) = entry.file_name().to_str() {
                // Skip Blizzard-internal directories (e.g. #RaidGroup)
                if name.starts_with('#') {
                    continue;
                }
                // A genuine account directory always contains a SavedVariables
                // subdirectory.  The account-wide SavedVariables folder that WoW
                // places alongside real account dirs fails this check.
                if entry.path().join("SavedVariables").is_dir() {
                    names.push(name.to_string());
                }
            }
        }
    }
    Ok(names)
}

/// Find the most recently modified WoWCombatLog*.txt in the Logs directory.
/// Falls back to the canonical name so callers always get a valid (if non-existent) path.
fn find_latest_combat_log(logs_dir: &Path) -> PathBuf {
    let fallback = logs_dir.join("WoWCombatLog.txt");
    let Ok(entries) = std::fs::read_dir(logs_dir) else {
        return fallback;
    };
    let mut best: Option<(PathBuf, std::time::SystemTime)> = None;
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if name_str.starts_with("WoWCombatLog") && name_str.ends_with(".txt") {
            if let Ok(meta) = entry.metadata() {
                if let Ok(modified) = meta.modified() {
                    if best.as_ref().map_or(true, |(_, t)| modified > *t) {
                        best = Some((entry.path(), modified));
                    }
                }
            }
        }
    }
    best.map(|(p, _)| p).unwrap_or(fallback)
}

/// Build the full WowPaths structure given a wow root and selected account name.
pub fn build_paths(wow_root: PathBuf, account_name: String) -> WowPaths {
    let logs_dir = wow_root.join("Logs");
    let combat_log = find_latest_combat_log(&logs_dir);
    let saved_variables = wow_root
        .join("WTF")
        .join("Account")
        .join(&account_name)
        .join("SavedVariables")
        .join("CombatLedger.lua");
    let generated_data = wow_root
        .join("Interface")
        .join("AddOns")
        .join("CombatLedger")
        .join("GeneratedData.lua");
    WowPaths {
        wow_root,
        combat_log,
        saved_variables,
        generated_data,
        account_name,
    }
}

/// Attempt a fully automated path resolution. Returns `Ok(paths)` if a single
/// account directory is found, or an `Err` that signals the caller to prompt the user.
pub fn auto_resolve() -> Result<WowPaths> {
    let root = detect_wow_root().context("WoW installation not found")?;
    let accounts = discover_account_names(&root)?;
    match accounts.len() {
        0 => anyhow::bail!("No Battle.net account directories found under WTF/Account"),
        1 => Ok(build_paths(root, accounts.into_iter().next().unwrap())),
        _ => anyhow::bail!(
            "Multiple Battle.net accounts found — user must select one: {:?}",
            accounts
        ),
    }
}
