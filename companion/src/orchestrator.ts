/**
 * orchestrator.ts — Singleton ParserOrchestrator instance
 *
 * Exported so both main.tsx (live log pipeline) and importer.ts (historical
 * log import) share the same orchestrator — meaning historicalSnapshots stays
 * in sync after an import without needing a companion restart.
 */

import { ParserOrchestrator } from "./parser/index.js";

export const orchestrator = new ParserOrchestrator();
