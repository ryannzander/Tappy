import { createEnv } from "@t3-oss/env-nextjs";
import { z } from "zod";

/**
 * Validated at boot so a missing key is a startup error, not a mystery 500 during the demo.
 * There is no DATABASE_URL: proposals live in memory for the length of a run.
 */
export const env = createEnv({
  server: {
    NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
    ANTHROPIC_API_KEY: z.string().min(1),
    SEPOLIA_RPC_URL: z.string().url(),
    AGENT_KEY: z.string().regex(/^0x[0-9a-fA-F]{64}$/),
    RELAYER_KEY: z.string().regex(/^0x[0-9a-fA-F]{64}$/),
  },
  client: {},
  runtimeEnv: {
    NODE_ENV: process.env.NODE_ENV,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    SEPOLIA_RPC_URL: process.env.SEPOLIA_RPC_URL,
    AGENT_KEY: process.env.AGENT_KEY,
    RELAYER_KEY: process.env.RELAYER_KEY,
  },
  skipValidation: !!process.env.SKIP_ENV_VALIDATION,
  emptyStringAsUndefined: true,
});
