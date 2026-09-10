import { toMobileProposal, toView } from "@tappy/protocol";
import { listProposals } from "~/server/tappy/store";
import { json } from "~/server/tappy/json";

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
  return json({
    pending: next ? toView(next, "sepolia") : null,
    // The full call as well as the view, so the device side can rebuild the digest itself
    // rather than signing whatever hash the server claims. Same rule as the phone.
    proposal: next ? toMobileProposal(next) : null,
    queued: pending.length,
  });
}
