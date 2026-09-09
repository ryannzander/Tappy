import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * The repo keeps one .env at the root — the contracts scripts and the bridge already read it.
 * Next only loads the one beside itself, so a key put in the obvious place was silently
 * invisible here, and the only symptom was the agent refusing to run.
 *
 * Deliberately does not overwrite anything already set: a real environment variable and
 * apps/hub/.env both still win over the root file.
 */
function loadRootEnv() {
  const here = dirname(fileURLToPath(import.meta.url));
  let text;
  try {
    text = readFileSync(resolve(here, "../../.env"), "utf8");
  } catch {
    return; // No root .env is a perfectly normal setup.
  }
  for (const line of text.split("\n")) {
    const match = /^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$/i.exec(line);
    if (!match) continue;
    const key = match[1];
    const rawValue = match[2];
    // noUncheckedIndexedAccess makes these possibly-undefined; a malformed line is skipped.
    if (!key || rawValue === undefined || process.env[key]) continue;
    process.env[key] = rawValue.trim().replace(/^["']|["']$/g, "");
  }
}

loadRootEnv();

// Imported after the env is populated, or validation runs against an empty environment.
await import("./src/env.js");

/** @type {import("next").NextConfig} */
const config = {
  // The workspace packages ship TypeScript, not a build. Next has to compile them itself.
  transpilePackages: ["@flippy/protocol", "@flippy/contracts"],

  webpack: (cfg) => {
    // Those packages use NodeNext-style specifiers — `export * from "./types.js"` pointing at a
    // types.ts. Without this alias webpack looks for a literal types.js, finds nothing, and the
    // failure surfaces as a 404 on every route rather than as an import error.
    cfg.resolve.extensionAlias = { ".js": [".ts", ".tsx", ".js"] };
    return cfg;
  },
};

export default config;
