import { toView } from "@flippy/protocol";
import { listProposals } from "~/server/flippy/store";
import { json } from "~/server/flippy/json";

export const dynamic = "force-dynamic";

/**
 * What the Flipper is waiting for. The bridge polls this about once a second — Vercel cannot
 * hold a WebSocket, and a second of latency is invisible next to a human picking up a device.
 *
 * Returns the oldest undecided proposal, so a queue drains in the order it was created.
 */
export async function GET() {
  const pending = listProposals(50)
    .filter((p) => p.status === "PENDING_HUMAN" && Math.floor(Date.now() / 1000) <= p.deadline)
    .sort((a, b) => a.createdAt - b.createdAt);

  const next = pending[0];
  return json({ pending: next ? toView(next, "sepolia") : null, queued: pending.length });
}
