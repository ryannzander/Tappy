import { z } from "zod";
import { hexSchema, toMobileProposal } from "@flippy/protocol";
import { getProposal, transition } from "~/server/flippy/store";
import { explorerTx, publicClient, relayExecute, verifyHumanSignature } from "~/server/flippy/chain";
import { fail, json } from "~/server/flippy/json";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const bodySchema = z.object({ deviceId: z.string().optional(), signature: hexSchema });

export async function POST(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const parsed = bodySchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return fail("expected { signature }");

  const p = getProposal(id);
  if (!p) return fail("unknown proposal", 404);
  if (p.status !== "PENDING_HUMAN") return fail(`proposal is ${p.status}, not PENDING_HUMAN`, 409);
  if (Math.floor(Date.now() / 1000) > p.deadline) {
    transition(p.id, "EXPIRED");
    return fail("proposal expired before it was approved", 409);
  }
  if (!p.agentSig) return fail("proposal has no agent signature — refusing to relay", 500);

  // Check the device's work before spending gas. On-chain this would revert as BadHumanSig,
  // which costs a transaction and tells us nothing about the cause.
  const curve = await verifyHumanSignature(p.id, parsed.data.signature);
  if (!curve) {
    return fail(
      "the signature does not verify against either of the gate's human keys. Either this " +
        "device is not registered, or it signed the wrong bytes — the Flipper signs the digest, " +
        "the Secure Enclave signs sha256(digest).",
      400,
    );
  }
  console.log(`[approve] ${p.id} approved via ${curve}`);

  let txHash;
  try {
    txHash = await relayExecute(p.call, p.deadline, p.agentSig, parsed.data.signature);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    transition(p.id, "FAILED", { error: message, humanSig: parsed.data.signature });
    return fail(message, 502);
  }

  const submitted = transition(p.id, "SUBMITTED", {
    txHash,
    humanSig: parsed.data.signature,
    decidedAt: Date.now(),
  });

  // Don't make the phone hold the connection open for 12-30 seconds of block time.
  // It polls GET /api/m/proposals/:id and watches the status change.
  void publicClient()
    .waitForTransactionReceipt({ hash: txHash })
    .then((r) => transition(p.id, r.status === "success" ? "EXECUTED" : "FAILED"))
    .catch((err) => transition(p.id, "FAILED", { error: err instanceof Error ? err.message : String(err) }));

  return json({ ...toMobileProposal(submitted), explorer: explorerTx(txHash) });
}
