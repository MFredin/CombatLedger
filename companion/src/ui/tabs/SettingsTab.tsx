import React, { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { getVersion } from "@tauri-apps/api/app";
import { purgeAllData } from "../../storage/sqlite.js";
import { orchestrator } from "../../orchestrator.js";

interface AppConfig {
  wow_root: string | null;
  account_name: string | null;
}

interface LaunchConfig {
  first_launch: boolean;
  launch_at_startup: boolean;
  startup_minimized: boolean;
}

interface UpdateInfo {
  version: string;
  notes: string;
}

type UpdateStatus = "idle" | "available" | "downloading" | "error";

interface Props {
  updateStatus: UpdateStatus;
  updateInfo: UpdateInfo | null;
  onCheckForUpdates: () => void;
  onInstallUpdate: () => void;
}

export default function SettingsTab({
  updateStatus,
  updateInfo,
  onCheckForUpdates,
  onInstallUpdate,
}: Props): React.ReactElement {
  const [appVersion, setAppVersion] = useState<string | null>(null);
  // WoW path / account
  const [wowPath, setWowPath]     = useState("");
  const [accounts, setAccounts]   = useState<string[]>([]);
  const [account, setAccount]     = useState("");
  const [pathError, setPathError] = useState<string | null>(null);

  // Startup prefs
  const [launchAtStartup, setLaunchAtStartup]   = useState(false);
  const [startupMinimized, setStartupMinimized] = useState(true);

  // Advanced section
  const [showAdvanced, setShowAdvanced]   = useState(false);
  const [purgeConfirm, setPurgeConfirm]   = useState(false);
  const [purging, setPurging]             = useState(false);

  // Feedback
  const [toast, setToast]   = useState<{ msg: string; ok: boolean } | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    Promise.all([
      invoke<AppConfig>("get_config"),
      invoke<LaunchConfig>("get_launch_config"),
      getVersion(),
    ])
      .then(([cfg, launch, ver]) => {
        if (cfg.wow_root) setWowPath(cfg.wow_root);
        if (cfg.account_name) setAccount(cfg.account_name);
        setLaunchAtStartup(launch.launch_at_startup);
        setStartupMinimized(launch.startup_minimized);
        setAppVersion(ver);
      })
      .catch(console.error);
  }, []);

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
      if (wowPath.trim() && account) {
        await invoke("set_wow_root", { root: wowPath.trim(), account });
      }
      await invoke("set_launch_config", { launchAtStartup, startupMinimized });
      setToast({ msg: "Settings saved.", ok: true });
    } catch (err) {
      setToast({ msg: String(err), ok: false });
    } finally {
      setSaving(false);
    }
  }

  async function handlePurge() {
    if (!purgeConfirm) {
      setPurgeConfirm(true);
      return;
    }
    setPurging(true);
    setToast(null);
    try {
      await purgeAllData();
      orchestrator.clearHistory();
      setToast({ msg: "All data purged. Do a /reload in WoW to clear the addon.", ok: true });
    } catch (err) {
      setToast({ msg: `Purge failed: ${String(err)}`, ok: false });
    } finally {
      setPurging(false);
      setPurgeConfirm(false);
    }
  }

  const canSave = !saving && (
    wowPath.trim() === "" || (accounts.length > 0 && account !== "") || account !== ""
  );

  return (
    <div className="settings-body" style={{ padding: "18px 20px" }}>
      {/* ── WoW installation ─────────────────────────────────────── */}
      <div className="field-group">
        <div className="field-group__label">WoW Installation Path</div>
        <div className="path-row">
          <input
            type="text"
            value={wowPath}
            onChange={(e) => handlePathChange(e.target.value)}
            placeholder="e.g. C:\Program Files (x86)\World of Warcraft\_retail_"
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
          Point to the game version folder, e.g. the _retail_ subfolder inside your WoW installation.
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

      {/* ── Startup ───────────────────────────────────────────────── */}
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

      <hr className="divider" />

      {/* ── Software updates ──────────────────────────────────────── */}
      <div className="field-group">
        <div className="field-group__label">Software Updates</div>
        <div className="field-group__desc" style={{ marginBottom: 8 }}>
          Current version: <strong>v{appVersion ?? "…"}</strong>
          {updateStatus === "available" && updateInfo && (
            <span style={{ color: "var(--accent)", marginLeft: 8 }}>
              — v{updateInfo.version} available
            </span>
          )}
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          {updateStatus !== "available" && (
            <button
              className="btn btn--secondary"
              onClick={onCheckForUpdates}
              disabled={updateStatus === "downloading"}
            >
              {updateStatus === "downloading" ? "Downloading…" : "Check for Updates"}
            </button>
          )}
          {updateStatus === "available" && updateInfo && (
            <>
              <button className="btn btn--primary" onClick={onInstallUpdate}>
                Install v{updateInfo.version} &amp; Restart
              </button>
              <button className="btn btn--secondary" onClick={onCheckForUpdates}>
                Re-check
              </button>
            </>
          )}
          {updateStatus === "error" && (
            <span style={{ fontSize: 11, color: "var(--red)" }}>
              Update check failed — check your connection.
            </span>
          )}
        </div>
      </div>

      <hr className="divider" />

      {/* ── Advanced toggle ───────────────────────────────────────── */}
      <div className="field-group">
        <label className="check-row">
          <input
            type="checkbox"
            checked={showAdvanced}
            onChange={(e) => {
              setShowAdvanced(e.target.checked);
              setPurgeConfirm(false);
            }}
          />
          <span className="check-row__label">Enable advanced features</span>
        </label>
        <div className="field-group__desc">
          Reveals destructive data management options. Handle with care.
        </div>
      </div>

      {showAdvanced && (
        <div className="field-group" style={{
          padding: "14px 16px",
          background: "color-mix(in srgb, var(--red) 5%, var(--bg-card))",
          border: "1px solid var(--red-dim)",
          borderRadius: "var(--radius-lg)",
        }}>
          <div className="field-group__label" style={{ color: "var(--red)" }}>Danger Zone</div>
          <div className="field-group__desc">
            Purge All Data permanently deletes every recorded session from the database and
            resets GeneratedData.lua to empty. This cannot be undone.
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 4 }}>
            {purgeConfirm ? (
              <>
                <span style={{ fontSize: 11, color: "var(--red)" }}>
                  Are you sure? This cannot be undone.
                </span>
                <button
                  className="btn btn--danger"
                  onClick={() => void handlePurge()}
                  disabled={purging}
                >
                  {purging ? "Purging…" : "Yes, Purge Everything"}
                </button>
                <button
                  className="btn btn--secondary"
                  onClick={() => setPurgeConfirm(false)}
                  disabled={purging}
                >
                  Cancel
                </button>
              </>
            ) : (
              <button
                className="btn btn--danger"
                onClick={() => void handlePurge()}
              >
                Purge All Data
              </button>
            )}
          </div>
        </div>
      )}

      {/* ── Footer ────────────────────────────────────────────────── */}
      <div style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "flex-end",
        gap: 10,
        paddingTop: 8,
        borderTop: "1px solid var(--border-visible)",
        marginTop: 4,
      }}>
        {toast && (
          <span className={`toast${toast.ok ? "" : " toast--error"}`} style={{ flex: 1 }}>
            {toast.msg}
          </span>
        )}
        <button
          className="btn btn--primary"
          onClick={() => void handleSave()}
          disabled={!canSave}
        >
          {saving ? "Saving…" : "Save"}
        </button>
      </div>
    </div>
  );
}
