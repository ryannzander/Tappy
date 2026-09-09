/**
 * Run `build` or `dev` with `SKIP_ENV_VALIDATION` to skip env validation. This is especially useful
 * for Docker builds.
 */
import "./src/env.js";

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
