import { toMobileProposal } from "@flippy/protocol";
import { getProposal } from "~/server/flippy/store";
import { explorerTx } from "~/server/flippy/chain";
import { fail, json } from "~/server/flippy/json";

export const dynamic = "force-dynamic";

export async function GET(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const p = getProposal(id);
  if (!p) return fail("unknown proposal", 404);
  return json({
    ...toMobileProposal(p),
    explorer: p.txHash ? explorerTx(p.txHash) : undefined,
  });
}
