// Prevents an additional console window on Windows in release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod database;
mod paths;
mod watcher;
mod writer;

use anyhow::Result;
use database::{Database, DistributionReport, EncounterOption, SessionInsert, SessionSummary, TrendReport};
use paths::WowPaths;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, State,
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

#[derive(Default)]
pub struct AppState {
    pub config: AppConfig,
    pub wow_paths: Option<WowPaths>,
    pub status: String,
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

    let size = writer::saved_variables_size(&paths.saved_variables);
    if size > 1_000_000 {
        eprintln!(
            "[writer] Warning: SavedVariables file is {}KB — consider purging old sessions",
            size / 1024
        );
    }

    writer::write_saved_variables(&paths.saved_variables, &lua_content)
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
// Main entry point
// ---------------------------------------------------------------------------

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
            let db_path = app
                .path()
                .app_data_dir()
                .expect("Failed to resolve app data dir")
                .join("combatledger.db");

            if let Some(parent) = db_path.parent() {
                std::fs::create_dir_all(parent).ok();
            }

            let database = Database::new(db_path).expect("Failed to open SQLite database");
            app.manage(database);

            let handle = app.handle().clone();
            let state_clone = shared_state.clone();

            // Attempt auto-resolve on startup.
            tauri::async_runtime::spawn(async move {
                let mut s = state_clone.lock().await;
                match paths::auto_resolve() {
                    Ok(wow_paths) => {
                        s.status = if wow_paths.combat_log.exists() {
                            "WoW log found ✓".to_string()
                        } else {
                            "Log not found".to_string()
                        };
                        s.config.wow_root =
                            Some(wow_paths.wow_root.to_string_lossy().into_owned());
                        s.config.account_name = Some(wow_paths.account_name.clone());

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
                        s.status = format!("Setup required: {e}");
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
            get_trend,
            get_distribution,
            get_encounters,
        ])
        .run(tauri::generate_context!())
        .expect("error while running CombatLedger companion");
}
