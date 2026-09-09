import { toMobileProposal } from "@tappy/protocol";
import { getProposal } from "~/server/tappy/store";
import { explorerTx } from "~/server/tappy/chain";
import { fail, json } from "~/server/tappy/json";

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
