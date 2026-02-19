/**
 * main.ts — Companion app entry point
 *
 * Listens for log-lines events emitted by the Tauri backend (watcher.rs),
 * feeds them into the parser pipeline, and calls the Rust write_session command
 * when a session completes.
 */

import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { ParserOrchestrator } from "./parser/index.js";

const orchestrator = new ParserOrchestrator();

/** Forward completed session Lua content to the Rust writer. */
async function onSessionComplete(luaContent: string): Promise<void> {
  try {
    await invoke("write_session", { luaContent });
    console.log("[main] Session written to SavedVariables.");
  } catch (err) {
    console.error("[main] Failed to write session:", err);
  }
}

async function main(): Promise<void> {
  // Load historical session snapshots from SQLite so the addon has full history
  // from the first fight even if the companion was restarted between sessions.
  await orchestrator.initialize();

  // Listen for batches of new log lines from the Rust watcher.
  await listen<string[]>("log-lines", async (event) => {
    const outputs = await orchestrator.processLines(event.payload);
    for (const output of outputs) {
      await onSessionComplete(output.luaContent);
    }
  });

  console.log("[main] CombatLedger Companion started — listening for log events.");
}

main().catch((err) => console.error("[main] Fatal error:", err));
