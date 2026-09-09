import { toMobileProposal } from "@flippy/protocol";
import { getProposal, transition } from "~/server/flippy/store";
import { fail, json } from "~/server/flippy/json";

export const dynamic = "force-dynamic";

/** A decline needs no signature. Nothing was authorised, so there is nothing to prove. */
export async function POST(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const p = getProposal(id);
  if (!p) return fail("unknown proposal", 404);
  if (p.status !== "PENDING_HUMAN") return fail(`proposal is ${p.status}, not PENDING_HUMAN`, 409);

  return json(toMobileProposal(transition(p.id, "REJECTED", { decidedAt: Date.now() })));
}
