use anyhow::Result;
use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use std::io::{Read, Seek, SeekFrom};
use std::path::PathBuf;
use std::sync::mpsc;
use std::time::Duration;
use tokio::sync::mpsc as tokio_mpsc;

/// A lightweight tail watcher for WoWCombatLog*.txt.
/// Delivers new lines to a tokio channel as they arrive.
/// Watches the Logs directory and dynamically tracks the newest
/// WoWCombatLog*.txt file, handling both timestamped names and log rotation.
pub struct LogWatcher {
    /// The Logs directory to scan for log files.
    logs_dir: PathBuf,
    /// The file currently being tailed (may change if WoW creates a new session file).
    current_path: Option<PathBuf>,
    /// Last known file size / byte offset; resets on log rotation or file switch.
    last_position: u64,
}

impl LogWatcher {
    /// `path` is the initial combat log path from `WowPaths`; only the parent
    /// directory is used so the watcher can discover timestamped files like
    /// `WoWCombatLog-021926_125113.txt` automatically.
    pub fn new(path: PathBuf) -> Self {
        let logs_dir = path
            .parent()
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| PathBuf::from("."));
        Self {
            logs_dir,
            current_path: None,
            last_position: 0,
        }
    }

    /// Scan the Logs directory for the newest WoWCombatLog*.txt file.
    fn find_latest_log(&self) -> Option<PathBuf> {
        let entries = std::fs::read_dir(&self.logs_dir).ok()?;
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
        best.map(|(p, _)| p)
    }

    /// Read any bytes written since `last_position`, split into lines, and
    /// advance the position.  Automatically switches to a newer log file if
    /// WoW creates a new session file (e.g. after a relog).
    fn read_new_lines(&mut self) -> Result<Vec<String>> {
        let latest = match self.find_latest_log() {
            Some(p) => p,
            None => return Ok(vec![]),
        };

        // Switch to the newer file and reset the position.
        if self.current_path.as_deref() != Some(latest.as_path()) {
            self.current_path = Some(latest.clone());
            self.last_position = 0;
        }

        let mut file = std::fs::File::open(&latest)?;
        let metadata = file.metadata()?;
        let file_size = metadata.len();

        // Detect log rotation: file is smaller than our last known position.
        if file_size < self.last_position {
            self.last_position = 0;
        }

        if file_size == self.last_position {
            return Ok(vec![]);
        }

        file.seek(SeekFrom::Start(self.last_position))?;
        let mut buf = String::new();
        file.read_to_string(&mut buf)?;
        self.last_position = file_size;

        let lines: Vec<String> = buf
            .lines()
            .map(|l| l.to_string())
            .filter(|l| !l.is_empty())
            .collect();
        Ok(lines)
    }

    /// Spawn the watcher loop.  New lines are sent over `tx`.
    /// The loop runs until `tx` is closed or an unrecoverable error occurs.
    pub async fn run(mut self, tx: tokio_mpsc::Sender<Vec<String>>) {
        let (notify_tx, notify_rx) = mpsc::channel::<notify::Result<Event>>();

        let mut watcher = match RecommendedWatcher::new(
            move |res| {
                // notify_tx.send silently fails if the receiver is gone — that's fine.
                let _ = notify_tx.send(res);
            },
            Config::default().with_poll_interval(Duration::from_millis(250)),
        ) {
            Ok(w) => w,
            Err(e) => {
                eprintln!("[watcher] Failed to create file watcher: {e}");
                return;
            }
        };

        // Watch the Logs directory — catches both modifications to existing files
        // and creation of new timestamped log files.
        if let Err(e) = watcher.watch(&self.logs_dir, RecursiveMode::NonRecursive) {
            eprintln!(
                "[watcher] Failed to watch directory {}: {e}",
                self.logs_dir.display()
            );
            return;
        }

        loop {
            // Block briefly waiting for a notify event.
            match notify_rx.recv_timeout(Duration::from_millis(500)) {
                Ok(Ok(Event { kind, .. })) => {
                    // We only care about Modify/Create events (WoW appends to the file).
                    if !matches!(kind, EventKind::Modify(_) | EventKind::Create(_)) {
                        continue;
                    }
                }
                Ok(Err(e)) => {
                    eprintln!("[watcher] Notify error: {e}");
                    continue;
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    // Poll even on timeout to catch any missed events.
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }

            match self.read_new_lines() {
                Ok(lines) if !lines.is_empty() => {
                    if tx.send(lines).await.is_err() {
                        // Receiver dropped — shut down.
                        break;
                    }
                }
                Ok(_) => {}
                Err(e) => eprintln!("[watcher] Read error: {e}"),
            }
        }
    }
}
