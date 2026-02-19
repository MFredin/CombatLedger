import React, { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";

interface AppConfig {
  wow_root: string | null;
  account_name: string | null;
}

interface LaunchConfig {
  first_launch: boolean;
  launch_at_startup: boolean;
  startup_minimized: boolean;
}

export default function SettingsWindow(): React.ReactElement {
  // WoW path / account
  const [wowPath, setWowPath]       = useState("");
  const [accounts, setAccounts]     = useState<string[]>([]);
  const [account, setAccount]       = useState("");
  const [pathError, setPathError]   = useState<string | null>(null);

  // Startup prefs
  const [launchAtStartup, setLaunchAtStartup]   = useState(false);
  const [startupMinimized, setStartupMinimized] = useState(true);

  // Feedback
  const [toast, setToast]     = useState<{ msg: string; ok: boolean } | null>(null);
  const [saving, setSaving]   = useState(false);

  // Load existing config on mount
  useEffect(() => {
    Promise.all([
      invoke<AppConfig>("get_config"),
      invoke<LaunchConfig>("get_launch_config"),
    ])
      .then(([cfg, launch]) => {
        if (cfg.wow_root) setWowPath(cfg.wow_root);
        if (cfg.account_name) setAccount(cfg.account_name);
        setLaunchAtStartup(launch.launch_at_startup);
        setStartupMinimized(launch.startup_minimized);
      })
      .catch(console.error);
  }, []);

  // When wowPath changes, clear stale accounts
  function handlePathChange(val: string) {
    setWowPath(val);
    setAccounts([]);
    setAccount("");
    setPathError(null);
  }

  async function detectAccounts() {
    setPathError(null);
    try {
      const found = await invoke<string[]>("list_accounts", { root: wowPath.trim() });
      if (found.length === 0) {
        setPathError("No accounts found — check the path points to your WoW installation folder.");
        setAccounts([]);
      } else {
        setAccounts(found);
        setAccount(found[0] ?? "");
      }
    } catch (err) {
      setPathError(String(err));
      setAccounts([]);
    }
  }

  async function handleSave() {
    setSaving(true);
    setToast(null);
    try {
      // Save WoW path if provided
      if (wowPath.trim() && account) {
        await invoke("set_wow_root", { root: wowPath.trim(), account });
      }

      // Save startup prefs
      await invoke("set_launch_config", {
        launchAtStartup,
        startupMinimized,
      });

      setToast({ msg: "Settings saved.", ok: true });
    } catch (err) {
      setToast({ msg: String(err), ok: false });
    } finally {
      setSaving(false);
    }
  }

  const canSave = !saving && (
    // Either a valid account is selected or no path was entered (startup-only change)
    (wowPath.trim() === "" || (accounts.length > 0 && account !== "") || account !== "")
  );

  return (
    <div className="settings-root">
      <div className="settings-header">
        <h1>CombatLedger Settings</h1>
      </div>

      <div className="settings-body">
        {/* ── WoW installation ─────────────────────────────────────── */}
        <div className="field-group">
          <div className="field-group__label">WoW Installation Path</div>
          <div className="path-row">
            <input
              type="text"
              value={wowPath}
              onChange={(e) => handlePathChange(e.target.value)}
              placeholder="e.g. C:\Program Files (x86)\World of Warcraft"
              spellCheck={false}
            />
            <button
              className="btn btn--secondary"
              onClick={() => void detectAccounts()}
              disabled={wowPath.trim() === ""}
            >
              Find Accounts
            </button>
          </div>
          {pathError && (
            <div className="field-group__desc" style={{ color: "var(--red)" }}>{pathError}</div>
          )}
          <div className="field-group__desc">
            Point to the root WoW folder (the one containing _retail_, _classic_, etc.).
          </div>
        </div>

        {/* ── Account ──────────────────────────────────────────────── */}
        <div className="field-group">
          <div className="field-group__label">Account</div>
          <select
            value={account}
            onChange={(e) => setAccount(e.target.value)}
            disabled={accounts.length === 0}
            style={{ maxWidth: 280 }}
          >
            {accounts.length === 0 && (
              <option value={account || ""}>{account || "— click Find Accounts —"}</option>
            )}
            {accounts.map((a) => (
              <option key={a} value={a}>{a}</option>
            ))}
          </select>
          <div className="field-group__desc">
            Your WTF account name — used to locate the SavedVariables file.
          </div>
        </div>

        <hr className="divider" />

        {/* ── Windows startup ───────────────────────────────────────── */}
        <div className="field-group">
          <div className="field-group__label">Startup</div>

          <label className="check-row">
            <input
              type="checkbox"
              checked={launchAtStartup}
              onChange={(e) => {
                setLaunchAtStartup(e.target.checked);
                if (!e.target.checked) setStartupMinimized(true);
              }}
            />
            <span className="check-row__label">Launch CombatLedger on Windows startup</span>
          </label>

          {launchAtStartup && (
            <div className="radio-group">
              <label className="check-row">
                <input
                  type="radio"
                  name="startup-mode"
                  checked={!startupMinimized}
                  onChange={() => setStartupMinimized(false)}
                />
                <span className="check-row__label">Open window on startup</span>
              </label>
              <label className="check-row">
                <input
                  type="radio"
                  name="startup-mode"
                  checked={startupMinimized}
                  onChange={() => setStartupMinimized(true)}
                />
                <span className="check-row__label">Start in background (tray icon only)</span>
              </label>
            </div>
          )}
        </div>
      </div>

      <div className="settings-footer">
        {toast && (
          <span className={`toast${toast.ok ? "" : " toast--error"}`}>{toast.msg}</span>
        )}
        <button className="btn btn--primary" onClick={() => void handleSave()} disabled={!canSave}>
          {saving ? "Saving…" : "Save"}
        </button>
      </div>
    </div>
  );
}
