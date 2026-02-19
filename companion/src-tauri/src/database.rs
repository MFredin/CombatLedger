// database.rs — SQLite persistence layer (Phase 3)
//
// Stores parsed session data to a local SQLite database, enabling trend
// analysis and percentile distribution beyond the 20-session SavedVariables
// limit.  The database lives in the Tauri app-data directory.

use anyhow::Result;
use rusqlite::{Connection, params};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Mutex;

// ---------------------------------------------------------------------------
// Schema
// ---------------------------------------------------------------------------

const SCHEMA_V1: &str = "
CREATE TABLE IF NOT EXISTS schema_version (
    version    INTEGER NOT NULL,
    applied_at TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS sessions (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    encounter_id        INTEGER NOT NULL,
    encounter_name      TEXT    NOT NULL,
    difficulty          INTEGER NOT NULL,
    group_size          INTEGER NOT NULL,
    start_time          INTEGER NOT NULL,
    end_time            INTEGER NOT NULL,
    duration_sec        INTEGER NOT NULL,
    success             INTEGER NOT NULL,
    pull_number         INTEGER NOT NULL,
    companion_version   TEXT    NOT NULL,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    total_deaths        INTEGER NOT NULL DEFAULT 0,
    interrupt_total     INTEGER NOT NULL DEFAULT 0,
    interrupt_hit       INTEGER NOT NULL DEFAULT 0,
    interrupt_rate_pct  REAL    NOT NULL DEFAULT 0,
    total_damage_done   INTEGER NOT NULL DEFAULT 0,
    total_healing_done  INTEGER NOT NULL DEFAULT 0,
    cc_avg_coverage_pct REAL    NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_sessions_encounter
    ON sessions(encounter_id, difficulty);
CREATE INDEX IF NOT EXISTS idx_sessions_time
    ON sessions(start_time DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_encounter_time
    ON sessions(encounter_id, difficulty, start_time DESC);

CREATE TABLE IF NOT EXISTS player_metrics (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    player_guid     TEXT    NOT NULL,
    player_name     TEXT    NOT NULL,
    player_class    TEXT    NOT NULL,
    player_spec     TEXT    NOT NULL,
    damage_done     INTEGER NOT NULL DEFAULT 0,
    healing_done    INTEGER NOT NULL DEFAULT 0,
    overhealing     INTEGER NOT NULL DEFAULT 0,
    dps             INTEGER NOT NULL DEFAULT 0,
    hps             INTEGER NOT NULL DEFAULT 0,
    interrupt_count INTEGER NOT NULL DEFAULT 0,
    death_count     INTEGER NOT NULL DEFAULT 0,
    cc_applied      INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_pm_session  ON player_metrics(session_id);
CREATE INDEX IF NOT EXISTS idx_pm_player   ON player_metrics(player_guid, session_id);
";

const SCHEMA_V2: &str = "
CREATE TABLE IF NOT EXISTS activity_log (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT    NOT NULL DEFAULT (datetime('now')),
    level     TEXT    NOT NULL DEFAULT 'info',
    message   TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_activity_time ON activity_log(timestamp DESC);
";

// ---------------------------------------------------------------------------
// Input types (received from TypeScript via Tauri invoke)
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct PlayerMetricInsert {
    pub player_guid: String,
    pub player_name: String,
    pub player_class: String,
    pub player_spec: String,
    pub damage_done: i64,
    pub healing_done: i64,
    pub overhealing: i64,
    pub dps: i64,
    pub hps: i64,
    pub interrupt_count: i64,
    pub death_count: i64,
    pub cc_applied: i64,
}

#[derive(Debug, Deserialize)]
pub struct SessionInsert {
    pub encounter_id: i64,
    pub encounter_name: String,
    pub difficulty: i64,
    pub group_size: i64,
    pub start_time: i64,
    pub end_time: i64,
    pub duration_sec: i64,
    pub success: bool,
    pub pull_number: i64,
    pub companion_version: String,
    pub total_deaths: i64,
    pub interrupt_total: i64,
    pub interrupt_hit: i64,
    pub interrupt_rate_pct: f64,
    pub total_damage_done: i64,
    pub total_healing_done: i64,
    pub cc_avg_coverage_pct: f64,
    pub players: Vec<PlayerMetricInsert>,
}

// ---------------------------------------------------------------------------
// Query result types (returned to TypeScript)
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, Clone)]
pub struct SessionSummary {
    pub id: i64,
    pub encounter_id: i64,
    pub encounter_name: String,
    pub difficulty: i64,
    pub group_size: i64,
    pub start_time: i64,
    pub end_time: i64,
    pub duration_sec: i64,
    pub success: bool,
    pub pull_number: i64,
    pub total_deaths: i64,
    pub interrupt_rate_pct: f64,
    pub total_damage_done: i64,
    pub total_healing_done: i64,
    pub cc_avg_coverage_pct: f64,
}

#[derive(Debug, Serialize, Clone)]
pub struct TrendPoint {
    pub session_id: i64,
    pub pull_number: i64,
    pub start_time: i64,
    pub success: bool,
    pub duration_sec: i64,
    pub total_deaths: i64,
    pub interrupt_rate_pct: f64,
    pub total_damage_done: i64,
    pub total_healing_done: i64,
    pub cc_avg_coverage_pct: f64,
}

#[derive(Debug, Serialize)]
pub struct TrendSummary {
    pub total_pulls: i64,
    pub kills: i64,
    pub wipes: i64,
    pub best_time_sec: i64,
    pub avg_deaths: f64,
    pub avg_interrupt_rate: f64,
    pub death_trend: f64,
    pub interrupt_trend: f64,
    pub dps_trend: f64,
}

#[derive(Debug, Serialize)]
pub struct TrendReport {
    pub encounter_id: i64,
    pub encounter_name: String,
    pub difficulty: i64,
    pub points: Vec<TrendPoint>,
    pub summary: TrendSummary,
}

#[derive(Debug, Serialize)]
pub struct PlayerDistribution {
    pub player_guid: String,
    pub player_name: String,
    pub player_class: String,
    pub player_spec: String,
    pub metric: String,
    pub current_value: i64,
    pub percentile: f64,
    pub total_samples: i64,
    pub min_value: i64,
    pub max_value: i64,
    pub median_value: i64,
}

#[derive(Debug, Serialize)]
pub struct DistributionReport {
    pub encounter_id: i64,
    pub encounter_name: String,
    pub difficulty: i64,
    pub players: Vec<PlayerDistribution>,
}

#[derive(Debug, Serialize)]
pub struct EncounterOption {
    pub encounter_id: i64,
    pub encounter_name: String,
    pub difficulty: i64,
    pub pull_count: i64,
    pub last_seen: i64,
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

pub struct Database {
    conn: Mutex<Connection>,
}

impl Database {
    /// Open (or create) the SQLite database at `db_path` and run migrations.
    pub fn new(db_path: PathBuf) -> Result<Self> {
        let conn = Connection::open(&db_path)?;
        // Enable WAL mode for better concurrent read performance.
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")?;
        let db = Self { conn: Mutex::new(conn) };
        db.migrate()?;
        Ok(db)
    }

    fn migrate(&self) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        let current: i64 = conn
            .query_row(
                "SELECT COALESCE(MAX(version), 0) FROM schema_version",
                [],
                |r| r.get(0),
            )
            .unwrap_or(0);

        if current < 1 {
            conn.execute_batch(SCHEMA_V1)?;
            conn.execute(
                "INSERT INTO schema_version (version) VALUES (1)",
                [],
            )?;
        }
        if current < 2 {
            conn.execute_batch(SCHEMA_V2)?;
            conn.execute(
                "INSERT INTO schema_version (version) VALUES (2)",
                [],
            )?;
        }
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Writes
    // -----------------------------------------------------------------------

    /// Insert a session and its player metrics in a single transaction.
    /// Returns the new session row id.
    pub fn insert_session(&self, s: SessionInsert) -> Result<i64> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO sessions (
                encounter_id, encounter_name, difficulty, group_size,
                start_time, end_time, duration_sec, success, pull_number,
                companion_version, total_deaths, interrupt_total, interrupt_hit,
                interrupt_rate_pct, total_damage_done, total_healing_done,
                cc_avg_coverage_pct
            ) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17)",
            params![
                s.encounter_id, s.encounter_name, s.difficulty, s.group_size,
                s.start_time, s.end_time, s.duration_sec, s.success as i64,
                s.pull_number, s.companion_version,
                s.total_deaths, s.interrupt_total, s.interrupt_hit,
                s.interrupt_rate_pct, s.total_damage_done, s.total_healing_done,
                s.cc_avg_coverage_pct,
            ],
        )?;
        let session_id = conn.last_insert_rowid();

        for p in &s.players {
            conn.execute(
                "INSERT INTO player_metrics (
                    session_id, player_guid, player_name, player_class, player_spec,
                    damage_done, healing_done, overhealing, dps, hps,
                    interrupt_count, death_count, cc_applied
                ) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13)",
                params![
                    session_id, p.player_guid, p.player_name, p.player_class, p.player_spec,
                    p.damage_done, p.healing_done, p.overhealing, p.dps, p.hps,
                    p.interrupt_count, p.death_count, p.cc_applied,
                ],
            )?;
        }

        Ok(session_id)
    }

    // -----------------------------------------------------------------------
    // Reads
    // -----------------------------------------------------------------------

    /// Paginated session history, optionally filtered by encounter/difficulty.
    pub fn get_session_history(
        &self,
        encounter_id: Option<i64>,
        difficulty: Option<i64>,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<SessionSummary>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, encounter_id, encounter_name, difficulty, group_size,
                    start_time, end_time, duration_sec, success, pull_number,
                    total_deaths, interrupt_rate_pct, total_damage_done,
                    total_healing_done, cc_avg_coverage_pct
             FROM sessions
             WHERE (?1 IS NULL OR encounter_id = ?1)
               AND (?2 IS NULL OR difficulty = ?2)
             ORDER BY start_time DESC
             LIMIT ?3 OFFSET ?4",
        )?;
        let rows = stmt.query_map(
            params![encounter_id, difficulty, limit, offset],
            |r| Ok(SessionSummary {
                id: r.get(0)?,
                encounter_id: r.get(1)?,
                encounter_name: r.get(2)?,
                difficulty: r.get(3)?,
                group_size: r.get(4)?,
                start_time: r.get(5)?,
                end_time: r.get(6)?,
                duration_sec: r.get(7)?,
                success: r.get::<_, i64>(8)? != 0,
                pull_number: r.get(9)?,
                total_deaths: r.get(10)?,
                interrupt_rate_pct: r.get(11)?,
                total_damage_done: r.get(12)?,
                total_healing_done: r.get(13)?,
                cc_avg_coverage_pct: r.get(14)?,
            }),
        )?;
        let mut results = Vec::new();
        for row in rows {
            results.push(row?);
        }
        Ok(results)
    }

    /// Trend data for the last N pulls on a given encounter+difficulty.
    pub fn get_trend(
        &self,
        encounter_id: i64,
        difficulty: i64,
        last_n: i64,
    ) -> Result<TrendReport> {
        let conn = self.conn.lock().unwrap();

        // Fetch last N sessions for this encounter ordered oldest→newest (for chart).
        let mut stmt = conn.prepare(
            "SELECT id, pull_number, start_time, success, duration_sec,
                    total_deaths, interrupt_rate_pct, total_damage_done,
                    total_healing_done, cc_avg_coverage_pct, encounter_name
             FROM sessions
             WHERE encounter_id = ?1 AND difficulty = ?2
             ORDER BY start_time DESC
             LIMIT ?3",
        )?;

        let mut points: Vec<TrendPoint> = stmt
            .query_map(params![encounter_id, difficulty, last_n], |r| {
                Ok(TrendPoint {
                    session_id: r.get(0)?,
                    pull_number: r.get(1)?,
                    start_time: r.get(2)?,
                    success: r.get::<_, i64>(3)? != 0,
                    duration_sec: r.get(4)?,
                    total_deaths: r.get(5)?,
                    interrupt_rate_pct: r.get(6)?,
                    total_damage_done: r.get(7)?,
                    total_healing_done: r.get(8)?,
                    cc_avg_coverage_pct: r.get(9)?,
                })
            })?
            .filter_map(|r| r.ok())
            .collect();

        // Reverse to chronological order for chart display.
        points.reverse();

        let encounter_name: String = conn
            .query_row(
                "SELECT encounter_name FROM sessions WHERE encounter_id = ?1 AND difficulty = ?2 LIMIT 1",
                params![encounter_id, difficulty],
                |r| r.get(0),
            )
            .unwrap_or_default();

        let summary = compute_trend_summary(&points);

        Ok(TrendReport {
            encounter_id,
            encounter_name,
            difficulty,
            points,
            summary,
        })
    }

    /// Percentile distribution for each player in `current_session_id`.
    pub fn get_distribution(
        &self,
        encounter_id: i64,
        difficulty: i64,
        current_session_id: i64,
    ) -> Result<DistributionReport> {
        let conn = self.conn.lock().unwrap();

        let encounter_name: String = conn
            .query_row(
                "SELECT encounter_name FROM sessions WHERE id = ?1",
                params![current_session_id],
                |r| r.get(0),
            )
            .unwrap_or_default();

        // Players in the current session.
        let mut cur_stmt = conn.prepare(
            "SELECT player_guid, player_name, player_class, player_spec,
                    dps, hps, interrupt_count
             FROM player_metrics WHERE session_id = ?1",
        )?;
        let current_players: Vec<(String, String, String, String, i64, i64, i64)> = cur_stmt
            .query_map(params![current_session_id], |r| {
                Ok((
                    r.get(0)?,
                    r.get(1)?,
                    r.get(2)?,
                    r.get(3)?,
                    r.get(4)?,
                    r.get(5)?,
                    r.get(6)?,
                ))
            })?
            .filter_map(|r| r.ok())
            .collect();

        let mut distributions = Vec::new();

        for (guid, name, class, spec, cur_dps, cur_hps, cur_int) in current_players {
            // Fetch all historical dps/hps/interrupt values for this player on this encounter.
            let mut hist_stmt = conn.prepare(
                "SELECT pm.dps, pm.hps, pm.interrupt_count
                 FROM player_metrics pm
                 JOIN sessions s ON s.id = pm.session_id
                 WHERE pm.player_guid = ?1
                   AND s.encounter_id = ?2
                   AND s.difficulty = ?3
                 ORDER BY s.start_time",
            )?;
            let hist: Vec<(i64, i64, i64)> = hist_stmt
                .query_map(params![guid, encounter_id, difficulty], |r| {
                    Ok((r.get(0)?, r.get(1)?, r.get(2)?))
                })?
                .filter_map(|r| r.ok())
                .collect();

            if hist.is_empty() {
                continue;
            }

            let dps_vals: Vec<i64> = hist.iter().map(|h| h.0).collect();
            let hps_vals: Vec<i64> = hist.iter().map(|h| h.1).collect();
            let int_vals: Vec<i64> = hist.iter().map(|h| h.2).collect();

            // DPS distribution
            if cur_dps > 0 || dps_vals.iter().any(|&v| v > 0) {
                distributions.push(PlayerDistribution {
                    player_guid: guid.clone(),
                    player_name: name.clone(),
                    player_class: class.clone(),
                    player_spec: spec.clone(),
                    metric: "dps".to_string(),
                    current_value: cur_dps,
                    percentile: percentile_rank(&dps_vals, cur_dps),
                    total_samples: dps_vals.len() as i64,
                    min_value: *dps_vals.iter().min().unwrap_or(&0),
                    max_value: *dps_vals.iter().max().unwrap_or(&0),
                    median_value: median(&dps_vals),
                });
            }

            // HPS distribution
            if cur_hps > 0 || hps_vals.iter().any(|&v| v > 0) {
                distributions.push(PlayerDistribution {
                    player_guid: guid.clone(),
                    player_name: name.clone(),
                    player_class: class.clone(),
                    player_spec: spec.clone(),
                    metric: "hps".to_string(),
                    current_value: cur_hps,
                    percentile: percentile_rank(&hps_vals, cur_hps),
                    total_samples: hps_vals.len() as i64,
                    min_value: *hps_vals.iter().min().unwrap_or(&0),
                    max_value: *hps_vals.iter().max().unwrap_or(&0),
                    median_value: median(&hps_vals),
                });
            }

            // Interrupt distribution (only if player has any history)
            if int_vals.iter().any(|&v| v > 0) {
                distributions.push(PlayerDistribution {
                    player_guid: guid,
                    player_name: name,
                    player_class: class,
                    player_spec: spec,
                    metric: "interrupts".to_string(),
                    current_value: cur_int,
                    percentile: percentile_rank(&int_vals, cur_int),
                    total_samples: int_vals.len() as i64,
                    min_value: *int_vals.iter().min().unwrap_or(&0),
                    max_value: *int_vals.iter().max().unwrap_or(&0),
                    median_value: median(&int_vals),
                });
            }
        }

        Ok(DistributionReport {
            encounter_id,
            encounter_name,
            difficulty,
            players: distributions,
        })
    }

    /// All distinct encounters seen in the database, for the UI dropdown.
    pub fn get_encounters(&self) -> Result<Vec<EncounterOption>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT encounter_id, encounter_name, difficulty,
                    COUNT(*) as pull_count, MAX(start_time) as last_seen
             FROM sessions
             GROUP BY encounter_id, difficulty
             ORDER BY last_seen DESC",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok(EncounterOption {
                encounter_id: r.get(0)?,
                encounter_name: r.get(1)?,
                difficulty: r.get(2)?,
                pull_count: r.get(3)?,
                last_seen: r.get(4)?,
            })
        })?;
        let mut results = Vec::new();
        for row in rows {
            results.push(row?);
        }
        Ok(results)
    }

    /// Append a line to the activity log.
    pub fn insert_activity(&self, level: &str, message: &str) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO activity_log (level, message) VALUES (?1, ?2)",
            params![level, message],
        )?;
        Ok(())
    }

    /// Return the most recent `limit` activity entries, newest first.
    pub fn get_activity_log(&self, limit: i64) -> Result<Vec<ActivityEntry>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, timestamp, level, message
             FROM activity_log
             ORDER BY id DESC
             LIMIT ?1",
        )?;
        let rows = stmt.query_map(params![limit], |r| {
            Ok(ActivityEntry {
                id: r.get(0)?,
                timestamp: r.get(1)?,
                level: r.get(2)?,
                message: r.get(3)?,
            })
        })?;
        let mut results = Vec::new();
        for row in rows {
            results.push(row?);
        }
        Ok(results)
    }
}

// ---------------------------------------------------------------------------
// Activity log
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, Clone)]
pub struct ActivityEntry {
    pub id: i64,
    pub timestamp: String,
    pub level: String,
    pub message: String,
}

// ---------------------------------------------------------------------------
// Statistics helpers
// ---------------------------------------------------------------------------

fn percentile_rank(values: &[i64], current: i64) -> f64 {
    if values.is_empty() {
        return 50.0;
    }
    let below = values.iter().filter(|&&v| v < current).count();
    let equal = values.iter().filter(|&&v| v == current).count();
    let n = values.len() as f64;
    ((below as f64 + 0.5 * equal as f64) / n) * 100.0
}

fn median(values: &[i64]) -> i64 {
    if values.is_empty() {
        return 0;
    }
    let mut sorted = values.to_vec();
    sorted.sort_unstable();
    let mid = sorted.len() / 2;
    if sorted.len() % 2 == 0 {
        (sorted[mid - 1] + sorted[mid]) / 2
    } else {
        sorted[mid]
    }
}

/// Linear regression slope over a series of values.
/// Positive slope = values increasing over time.
fn linear_slope(values: &[f64]) -> f64 {
    let n = values.len() as f64;
    if n < 2.0 {
        return 0.0;
    }
    let x_mean = (n - 1.0) / 2.0;
    let y_mean: f64 = values.iter().sum::<f64>() / n;
    let mut num = 0.0_f64;
    let mut den = 0.0_f64;
    for (i, &y) in values.iter().enumerate() {
        let x = i as f64;
        num += (x - x_mean) * (y - y_mean);
        den += (x - x_mean) * (x - x_mean);
    }
    if den == 0.0 {
        0.0
    } else {
        num / den
    }
}

fn compute_trend_summary(points: &[TrendPoint]) -> TrendSummary {
    if points.is_empty() {
        return TrendSummary {
            total_pulls: 0,
            kills: 0,
            wipes: 0,
            best_time_sec: 0,
            avg_deaths: 0.0,
            avg_interrupt_rate: 0.0,
            death_trend: 0.0,
            interrupt_trend: 0.0,
            dps_trend: 0.0,
        };
    }

    let total = points.len() as i64;
    let kills = points.iter().filter(|p| p.success).count() as i64;
    let wipes = total - kills;

    let best_time = points
        .iter()
        .filter(|p| p.success)
        .map(|p| p.duration_sec)
        .min()
        .unwrap_or(0);

    let n = points.len() as f64;
    let avg_deaths = points.iter().map(|p| p.total_deaths as f64).sum::<f64>() / n;
    let avg_interrupt_rate = points.iter().map(|p| p.interrupt_rate_pct).sum::<f64>() / n;

    let death_vals: Vec<f64> = points.iter().map(|p| p.total_deaths as f64).collect();
    let interrupt_vals: Vec<f64> = points.iter().map(|p| p.interrupt_rate_pct).collect();
    let dps_vals: Vec<f64> = points.iter().map(|p| {
        if p.duration_sec > 0 {
            p.total_damage_done as f64 / p.duration_sec as f64
        } else {
            0.0
        }
    }).collect();

    TrendSummary {
        total_pulls: total,
        kills,
        wipes,
        best_time_sec: best_time,
        avg_deaths: (avg_deaths * 10.0).round() / 10.0,
        avg_interrupt_rate: (avg_interrupt_rate * 10.0).round() / 10.0,
        death_trend: (linear_slope(&death_vals) * 100.0).round() / 100.0,
        interrupt_trend: (linear_slope(&interrupt_vals) * 100.0).round() / 100.0,
        dps_trend: linear_slope(&dps_vals).round(),
    }
}
