import { privateKeyToAccount } from "viem/accounts";
import type { Address, Hex } from "viem";
import {
  MockHumanSigner,
  chainByKey,
  mobileProposalSchema,
  proposalDigest,
  proposalViewSchema,
  type HumanSigner,
} from "@tappy/protocol";
import { loadConfig } from "./config.js";
import { FlipperCli } from "./flipperCli.js";
import { FlipperHumanSigner } from "./flipperSigner.js";
import { LocalHumanSigner } from "./localSigner.js";
import { NfcHumanSigner } from "./nfcSigner.js";

/** Fast enough to feel instant next to a human reaching for a device, slow enough to be free. */
const POLL_MS = 1000;
const ERROR_BACKOFF_MS = 3000;
/** How long the device gets to answer before we give up on this proposal and re-poll. */
const APPROVAL_TIMEOUT_MS = 120_000;

async function buildSigner(cfg: ReturnType<typeof loadConfig>): Promise<HumanSigner> {
  const chain = chainByKey(cfg.CHAIN_KEY);
  const common = {
    privateKey: cfg.HUMAN_KEY as Hex,
    chainId: chain.chainId,
    gate: cfg.GATE_ADDRESS as Address,
  };

  if (cfg.SIGNER_KIND === "mock") {
    console.log("[bridge] SIGNER_KIND=mock — approving from this terminal, no hardware used");
    return new MockHumanSigner({ ...common, mode: "cli" });
  }

  if (cfg.SIGNER_KIND === "local" || cfg.SIGNER_KIND === "auto") {
    const auto = cfg.SIGNER_KIND === "auto";
    console.log(
      `[bridge] SIGNER_KIND=${cfg.SIGNER_KIND} — the terminal is standing in for the Flipper` +
        (auto ? ", approving everything automatically" : ""),
    );
    return new LocalHumanSigner({ privateKey: cfg.HUMAN_KEY as Hex, auto });
  }

  const cli = new FlipperCli(cfg.FLIPPER_PORT, cfg.FLIPPER_BAUD);
  await cli.open();
  console.log(`[bridge] Flipper connected on ${cfg.FLIPPER_PORT}`);

  if (cfg.SIGNER_KIND === "nfc") {
    const allowedUids = cfg.ALLOWED_UIDS.split(",")
      .map((u) => u.trim().replace(/[^0-9A-Fa-f]/g, "").toLowerCase())
      .filter(Boolean);
    console.log(
      allowedUids.length > 0
        ? `[bridge] SIGNER_KIND=nfc — tap to approve, ${allowedUids.length} tag(s) registered`
        : "[bridge] SIGNER_KIND=nfc — tap to approve, ANY tag accepted (set ALLOWED_UIDS to restrict)",
    );
    return new NfcHumanSigner({
      privateKey: cfg.HUMAN_KEY as Hex,
      cli,
      allowedUids,
      command: cfg.FLIPPER_NFC_CMD,
    });
  }

  await cli.mkdir("/ext/apps_data/tappy");
  return new FlipperHumanSigner({ ...common, cli });
}

async function main(): Promise<void> {
  const cfg = loadConfig();
  const account = privateKeyToAccount(cfg.HUMAN_KEY as Hex);
  console.log(`[bridge] human address ${account.address}`);
  console.log("[bridge] the gate must be deployed with HUMAN_K1_ADDRESS set to exactly that");

  const signer = await buildSigner(cfg);
  const base = cfg.HUB_URL.replace(/\/$/, "");
  console.log(`[bridge] polling ${base}/api/bridge/pending every ${POLL_MS}ms`);

  // Proposals we have already answered. The hub moves them out of PENDING_HUMAN the moment
  // it accepts our decision, but polling is not instant — without this we would show the
  // same request on the device twice.
  const answered = new Set<string>();

  for (;;) {
    try {
      const res = await fetch(`${base}/api/bridge/pending`);
      if (!res.ok) throw new Error(`hub returned ${res.status}: ${await res.text()}`);
      const body = (await res.json()) as { pending: unknown; proposal: unknown };

      if (!body.pending) {
        await sleep(POLL_MS);
        continue;
      }

      const view = proposalViewSchema.parse(body.pending);

      // Rebuild the digest from the call rather than trusting the one the hub sent. This is the
      // same rule the phone follows: a hub that lied about what a proposal does cannot get a
      // signature out of this process either.
      const proposal = mobileProposalSchema.parse(body.proposal);
      const recomputed = proposalDigest({
        chainId: proposal.chainId,
        gate: proposal.gate,
        nonce: proposal.nonce,
        call: proposal.call,
        deadline: proposal.deadline,
      });
      if (recomputed.toLowerCase() !== view.digest.toLowerCase()) {
        // Loud and fatal: this is either a bug or an attack, and neither should be retried.
        throw new Error(
          `digest mismatch — refusing to sign.\n  hub sent:   ${view.digest}\n  recomputed: ${recomputed}`,
        );
      }
      if (answered.has(view.id)) {
        await sleep(POLL_MS);
        continue;
      }

      console.log(`[bridge] ${view.action} ${view.amount} -> ${view.counterparty}  (${view.short})`);
      const decision = await signer.requestApproval(view, APPROVAL_TIMEOUT_MS);
      answered.add(view.id);

      const path = decision.approved ? "approve" : "reject";
      const post = await fetch(`${base}/api/m/proposals/${view.id}/${path}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(decision.approved ? { signature: decision.humanSig } : {}),
      });
      const result = await post.text();

      // A rejected signature means the gate would have reverted. That is worth shouting about:
      // it usually means the gate was deployed with a different human address than this key.
      console.log(`[bridge] -> ${decision.approved ? "APPROVED" : "REJECTED"} (hub: ${post.status}) ${result}`);
    } catch (err) {
      console.error("[bridge]", err instanceof Error ? err.message : err);
      await sleep(ERROR_BACKOFF_MS);
    }
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
