use anyhow::Result;
use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use std::io::{Read, Seek, SeekFrom};
use std::path::PathBuf;
use std::sync::mpsc;
use std::time::Duration;
use tokio::sync::mpsc as tokio_mpsc;

/// A lightweight tail watcher for WoWCombatLog.txt.
/// Delivers new lines to a tokio channel as they arrive.
pub struct LogWatcher {
    path: PathBuf,
    /// Last known file size / byte offset; resets on log rotation.
    last_position: u64,
}

impl LogWatcher {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            last_position: 0,
        }
    }

    /// Read any bytes written since `last_position`, split into lines, and
    /// advance the position.  Returns the new lines (without trailing newlines).
    fn read_new_lines(&mut self) -> Result<Vec<String>> {
        let mut file = std::fs::File::open(&self.path)?;
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

        // Watch the parent directory in case the file doesn't exist yet.
        let watch_dir = self
            .path
            .parent()
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| PathBuf::from("."));

        if let Err(e) = watcher.watch(&watch_dir, RecursiveMode::NonRecursive) {
            eprintln!("[watcher] Failed to watch directory {}: {e}", watch_dir.display());
            return;
        }

        loop {
            // Block briefly waiting for a notify event.
            match notify_rx.recv_timeout(Duration::from_millis(500)) {
                Ok(Ok(Event { kind, .. })) => {
                    // We only care about Modify events (WoW appends to the file).
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

            if !self.path.exists() {
                continue;
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
