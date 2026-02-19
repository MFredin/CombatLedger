// Prevents an additional console window on Windows in release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod database;
mod paths;
mod watcher;
mod writer;

use anyhow::Result;
use database::{ActivityEntry, Database, DistributionReport, EncounterOption, SessionInsert, SessionSummary, TrendReport};
use paths::WowPaths;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Emitter, Manager, State,
};
use tokio::sync::{mpsc, Mutex};

// ---------------------------------------------------------------------------
// App state
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub wow_root: Option<String>,
    pub account_name: Option<String>,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            wow_root: None,
            account_name: None,
        }
    }
}

/// Persisted startup/launch preferences (stored as JSON in app-data).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LaunchConfig {
    /// True only on the very first run; cleared after the window is shown once.
    pub first_launch: bool,
    /// Whether to register this app in the OS autostart registry.
    pub launch_at_startup: bool,
    /// When launching at startup, stay hidden in the tray (true) or show the
    /// window immediately (false).
    pub startup_minimized: bool,
}

impl Default for LaunchConfig {
    fn default() -> Self {
        Self {
            first_launch: true,
            launch_at_startup: false,
            startup_minimized: true,
        }
    }
}

#[derive(Default)]
pub struct AppState {
    pub config: AppConfig,
    pub launch_config: LaunchConfig,
    pub wow_paths: Option<WowPaths>,
    pub status: String,
}

// ---------------------------------------------------------------------------
// Launch-config persistence helpers
// ---------------------------------------------------------------------------

fn load_launch_config(path: &std::path::Path) -> LaunchConfig {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn save_launch_config(path: &std::path::Path, cfg: &LaunchConfig) {
    if let Ok(json) = serde_json::to_string_pretty(cfg) {
        let _ = std::fs::write(path, json);
    }
}

type SharedState = Arc<Mutex<AppState>>;

// ---------------------------------------------------------------------------
// Tauri commands — existing
// ---------------------------------------------------------------------------

#[tauri::command]
async fn get_status(state: State<'_, SharedState>) -> Result<String, String> {
    let s = state.lock().await;
    Ok(s.status.clone())
}

#[tauri::command]
async fn get_config(state: State<'_, SharedState>) -> Result<AppConfig, String> {
    let s = state.lock().await;
    Ok(s.config.clone())
}

#[tauri::command]
async fn set_wow_root(
    root: String,
    account: String,
    state: State<'_, SharedState>,
) -> Result<String, String> {
    let mut s = state.lock().await;
    let root_path = std::path::PathBuf::from(&root);

    match paths::discover_account_names(&root_path) {
        Ok(accounts) if accounts.contains(&account) => {
            let wow_paths = paths::build_paths(root_path, account.clone());
            s.config.wow_root = Some(root.clone());
            s.config.account_name = Some(account);
            s.status = if wow_paths.combat_log.exists() {
                "WoW log found ✓".to_string()
            } else {
                "Log not found".to_string()
            };
            s.wow_paths = Some(wow_paths);
            Ok(s.status.clone())
        }
        Ok(_) => Err(format!("Account '{}' not found in WTF/Account", account)),
        Err(e) => Err(e.to_string()),
    }
}

#[tauri::command]
async fn list_accounts(root: String) -> Result<Vec<String>, String> {
    let root_path = std::path::PathBuf::from(&root);
    paths::discover_account_names(&root_path).map_err(|e| e.to_string())
}

/// Called by the TypeScript parser side when it has finished processing a session
/// and provides the serialised Lua content to write to disk.
#[tauri::command]
async fn write_session(
    lua_content: String,
    state: State<'_, SharedState>,
) -> Result<(), String> {
    let s = state.lock().await;
    let paths = s
        .wow_paths
        .as_ref()
        .ok_or_else(|| "WoW paths not configured".to_string())?;

    // Write CombatLedgerDB to the addon's GeneratedData.lua rather than the
    // WoW-managed SavedVariables file.  WoW completely rewrites CombatLedger.lua
    // on every /reload (wiping anything it doesn't own), but it never touches
    // files in Interface/AddOns/.  GeneratedData.lua is listed first in the .toc
    // so WoW loads it on every /reload, giving the addon fresh companion data.
    let size = writer::saved_variables_size(&paths.generated_data);
    if size > 1_000_000 {
        eprintln!(
            "[writer] Warning: GeneratedData.lua is {}KB — consider purging old sessions",
            size / 1024
        );
    }

    writer::write_saved_variables(&paths.generated_data, &lua_content)
        .map_err(|e| e.to_string())
}

// ---------------------------------------------------------------------------
// Tauri commands — Phase 3 SQLite
// ---------------------------------------------------------------------------

/// Store a parsed session to SQLite and return the new session DB row id.
#[tauri::command]
async fn store_session(
    session: SessionInsert,
    db: State<'_, Database>,
) -> Result<i64, String> {
    db.insert_session(session).map_err(|e| e.to_string())
}

/// Paginated session history browser, optionally filtered by encounter/difficulty.
#[tauri::command]
async fn get_session_history(
    encounter_id: Option<i64>,
    difficulty: Option<i64>,
    limit: i64,
    offset: i64,
    db: State<'_, Database>,
) -> Result<Vec<SessionSummary>, String> {
    db.get_session_history(encounter_id, difficulty, limit, offset)
        .map_err(|e| e.to_string())
}

/// Return the most recent `limit` session snapshots (JSON strings) for
/// bootstrapping the orchestrator's history on startup.
#[tauri::command]
async fn get_session_snapshots(
    limit: i64,
    db: State<'_, Database>,
) -> Result<Vec<String>, String> {
    db.get_session_snapshots(limit).map_err(|e| e.to_string())
}

/// Return true if a session with this encounter_id + start_time already exists.
/// Used for deduplication when importing historical combat logs.
#[tauri::command]
async fn session_exists(
    encounter_id: i64,
    start_time: i64,
    db: State<'_, Database>,
) -> Result<bool, String> {
    db.session_exists(encounter_id, start_time).map_err(|e| e.to_string())
}

/// Open a native OS file-picker filtered to .txt files and return the chosen path.
/// Returns null if the user cancels.
#[tauri::command]
async fn pick_log_file() -> Result<Option<String>, String> {
    let handle = rfd::AsyncFileDialog::new()
        .add_filter("WoW Combat Log", &["txt"])
        .set_title("Select WoW Combat Log")
        .pick_file()
        .await;
    Ok(handle.map(|f| f.path().to_string_lossy().into_owned()))
}

/// Read a combat-log file line by line, emitting batches via the "import-lines"
/// event.  Returns immediately — streaming happens in a background task.
/// Emits "import-done" when the file is fully read (or on error).
#[tauri::command]
async fn start_log_import(
    path: String,
    app_handle: tauri::AppHandle,
) -> Result<(), String> {
    tokio::spawn(async move {
        use std::io::BufRead;

        let file = match std::fs::File::open(&path) {
            Ok(f) => f,
            Err(e) => {
                eprintln!("[import] Cannot open {path}: {e}");
                let _ = app_handle.emit("import-done", ());
                return;
            }
        };
        let total_bytes = file.metadata().map(|m| m.len()).unwrap_or(0);
        let reader = std::io::BufReader::new(file);

        let mut batch: Vec<String> = Vec::with_capacity(1000);
        let mut bytes_read: u64 = 0;

        for line in reader.lines() {
            let line = match line {
                Ok(l) => l,
                Err(_) => break,
            };
            bytes_read += line.len() as u64 + 1; // +1 for newline
            batch.push(line);

            if batch.len() >= 1000 {
                let _ = app_handle.emit("import-lines", serde_json::json!({
                    "lines": batch,
                    "bytesRead": bytes_read,
                    "totalBytes": total_bytes,
                }));
                batch = Vec::with_capacity(1000);
            }
        }

        if !batch.is_empty() {
            let _ = app_handle.emit("import-lines", serde_json::json!({
                "lines": batch,
                "bytesRead": bytes_read,
                "totalBytes": total_bytes,
            }));
        }

        let _ = app_handle.emit("import-done", ());
    });
    Ok(())
}

/// Pull-over-pull trend data for the last N sessions on a given encounter.
#[tauri::command]
async fn get_trend(
    encounter_id: i64,
    difficulty: i64,
    last_n: i64,
    db: State<'_, Database>,
) -> Result<TrendReport, String> {
    db.get_trend(encounter_id, difficulty, last_n)
        .map_err(|e| e.to_string())
}

/// Percentile distribution for each player in the given session.
#[tauri::command]
async fn get_distribution(
    encounter_id: i64,
    difficulty: i64,
    current_session_id: i64,
    db: State<'_, Database>,
) -> Result<DistributionReport, String> {
    db.get_distribution(encounter_id, difficulty, current_session_id)
        .map_err(|e| e.to_string())
}

/// List all distinct encounters in the database (for UI dropdowns).
#[tauri::command]
async fn get_encounters(db: State<'_, Database>) -> Result<Vec<EncounterOption>, String> {
    db.get_encounters().map_err(|e| e.to_string())
}

// ---------------------------------------------------------------------------
// Tauri commands — launch config & activity log
// ---------------------------------------------------------------------------

#[tauri::command]
async fn get_launch_config(state: State<'_, SharedState>) -> Result<LaunchConfig, String> {
    let s = state.lock().await;
    Ok(s.launch_config.clone())
}

#[tauri::command]
async fn set_launch_config(
    launch_at_startup: bool,
    startup_minimized: bool,
    state: State<'_, SharedState>,
    app: tauri::AppHandle,
) -> Result<(), String> {
    use tauri_plugin_autostart::ManagerExt;
    let mut s = state.lock().await;
    s.launch_config.launch_at_startup = launch_at_startup;
    s.launch_config.startup_minimized = startup_minimized;

    let cfg_path = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join("launch_config.json");
    save_launch_config(&cfg_path, &s.launch_config);

    if launch_at_startup {
        app.autolaunch().enable().map_err(|e| e.to_string())?;
    } else {
        app.autolaunch().disable().map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
async fn log_activity(
    level: String,
    message: String,
    db: State<'_, Database>,
) -> Result<(), String> {
    db.insert_activity(&level, &message).map_err(|e| e.to_string())
}

#[tauri::command]
async fn get_activity_log(
    limit: i64,
    db: State<'_, Database>,
) -> Result<Vec<ActivityEntry>, String> {
    db.get_activity_log(limit).map_err(|e| e.to_string())
}

// ---------------------------------------------------------------------------
// Tauri commands — auto-updater
// ---------------------------------------------------------------------------

/// Returned to the frontend when a newer version is available.
#[derive(Debug, Clone, Serialize)]
struct UpdateInfo {
    version: String,
    notes: String,
}

/// Check GitHub for a newer release.  Returns `None` when already up-to-date.
/// Silent network failures are propagated as `Err` so the caller can ignore them.
#[tauri::command]
async fn check_update(app: tauri::AppHandle) -> Result<Option<UpdateInfo>, String> {
    use tauri_plugin_updater::UpdaterExt;
    let update = app
        .updater()
        .map_err(|e| e.to_string())?
        .check()
        .await
        .map_err(|e| e.to_string())?;
    Ok(update.map(|u| UpdateInfo {
        version: u.version.clone(),
        notes: u.body.clone().unwrap_or_default(),
    }))
}

/// Download and install the latest release, then exit so the installer can run.
/// On Windows (NSIS) the installer launches and the process exits automatically.
/// On macOS the app restarts into the new version.
#[tauri::command]
async fn install_update(app: tauri::AppHandle) -> Result<(), String> {
    use tauri_plugin_updater::UpdaterExt;
    let update = app
        .updater()
        .map_err(|e| e.to_string())?
        .check()
        .await
        .map_err(|e| e.to_string())?;
    if let Some(update) = update {
        update
            .download_and_install(|_chunk, _total| {}, || {})
            .await
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}



fn main() {
    let shared_state: SharedState = Arc::new(Mutex::new(AppState::default()));

    tauri::Builder::default()
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec!["--minimized"]),
        ))
        .plugin(tauri_plugin_updater::Builder::new().build())
        .manage(shared_state.clone())
        .setup(move |app| {
            // Initialise SQLite database in the Tauri app-data directory.
            let data_dir = app
                .path()
                .app_data_dir()
                .expect("Failed to resolve app data dir");
            std::fs::create_dir_all(&data_dir).ok();

            let db_path = data_dir.join("combatledger.db");
            let database = Database::new(db_path).expect("Failed to open SQLite database");

            // ----------------------------------------------------------------
            // Launch config — load, apply window-visibility logic, persist.
            // ----------------------------------------------------------------
            let cfg_path = data_dir.join("launch_config.json");
            let mut launch_config = load_launch_config(&cfg_path);
            let is_first_launch = launch_config.first_launch;
            let startup_minimized = launch_config.startup_minimized;

            if is_first_launch {
                launch_config.first_launch = false;
                save_launch_config(&cfg_path, &launch_config);
            }

            // Show the main window unless we were started by the OS autostart
            // mechanism AND the user wants a tray-only startup.
            let launched_minimized = std::env::args().any(|a| a == "--minimized");
            let should_show = is_first_launch || !launched_minimized || !startup_minimized;
            if should_show {
                if let Some(win) = app.get_webview_window("main") {
                    let _ = win.show();
                    let _ = win.set_focus();
                }
            }

            // Populate shared state with the loaded launch config.
            {
                let mut s = shared_state.blocking_lock();
                s.launch_config = launch_config;
            }

            app.manage(database);

            let handle = app.handle().clone();
            let state_clone = shared_state.clone();

            // Attempt auto-resolve on startup.
            tauri::async_runtime::spawn(async move {
                let mut s = state_clone.lock().await;
                match paths::auto_resolve() {
                    Ok(wow_paths) => {
                        let log_exists = wow_paths.combat_log.exists();
                        s.status = if log_exists {
                            "Watching — WoW log found".to_string()
                        } else {
                            "WoW found — log not yet created".to_string()
                        };
                        s.config.wow_root =
                            Some(wow_paths.wow_root.to_string_lossy().into_owned());
                        s.config.account_name = Some(wow_paths.account_name.clone());

                        let db = handle.state::<Database>();
                        let _ = db.insert_activity(
                            "info",
                            &format!("CombatLedger started — account: {}", wow_paths.account_name),
                        );
                        if log_exists {
                            let _ = db.insert_activity("info", "Combat log found, watcher active");
                        } else {
                            let _ = db.insert_activity("warn", "Combat log not yet present — enter a zone to create it");
                        }
                        let _ = handle.emit("status-update", s.status.clone());

                        // Spawn the log watcher.
                        let log_path = wow_paths.combat_log.clone();
                        let (tx, mut rx) = mpsc::channel::<Vec<String>>(256);
                        let watcher = watcher::LogWatcher::new(log_path);

                        tauri::async_runtime::spawn(async move {
                            watcher.run(tx).await;
                        });

                        let handle_inner = handle.clone();
                        tauri::async_runtime::spawn(async move {
                            while let Some(lines) = rx.recv().await {
                                // Forward new log lines to the TypeScript front-end.
                                let _ = handle_inner.emit("log-lines", lines);
                            }
                        });

                        s.wow_paths = Some(wow_paths);
                    }
                    Err(e) => {
                        s.status = "Setup required — WoW path not found".to_string();
                        let db = handle.state::<Database>();
                        let _ = db.insert_activity("warn", &format!("Auto-resolve failed: {e} — manual setup required"));
                        let _ = handle.emit("status-update", s.status.clone());
                        // Open settings window so user can manually set path.
                        if let Some(win) = handle.get_webview_window("settings") {
                            let _ = win.show();
                        }
                    }
                }
            });

            // Build tray icon.
            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let settings = MenuItem::with_id(app, "settings", "Settings", true, None::<&str>)?;
            let open = MenuItem::with_id(app, "open", "Open", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&open, &settings, &quit])?;

            TrayIconBuilder::new()
                .menu(&menu)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => app.exit(0),
                    "settings" => {
                        if let Some(win) = app.get_webview_window("settings") {
                            let _ = win.show();
                            let _ = win.set_focus();
                        }
                    }
                    "open" => {
                        if let Some(win) = app.get_webview_window("main") {
                            let _ = win.show();
                            let _ = win.set_focus();
                        }
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        if let Some(win) = tray.app_handle().get_webview_window("main") {
                            let _ = win.show();
                            let _ = win.set_focus();
                        }
                    }
                })
                .build(app)?;

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_status,
            get_config,
            set_wow_root,
            list_accounts,
            write_session,
            store_session,
            get_session_history,
            get_session_snapshots,
            session_exists,
            pick_log_file,
            start_log_import,
            get_trend,
            get_distribution,
            get_encounters,
            get_launch_config,
            set_launch_config,
            log_activity,
            get_activity_log,
            check_update,
            install_update,
        ])
        .run(tauri::generate_context!())
        .expect("error while running CombatLedger companion");
}
