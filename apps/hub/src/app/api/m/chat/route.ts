import { z } from "zod";
import { runTurn } from "~/server/agent/loop";
import { listMessages, listProposals } from "~/server/tappy/store";
import { fail, json } from "~/server/tappy/json";

export const dynamic = "force-dynamic";
/** A tool-calling turn on Opus can take a while; don't let the platform cut it short. */
export const maxDuration = 120;

export async function GET() {
  return json({ messages: listMessages(), proposals: listProposals(20) });
}

export async function POST(req: Request) {
  const parsed = z
    .object({ text: z.string().min(1) })
    .safeParse(await req.json().catch(() => null));
  if (!parsed.success) return fail("expected { text }");

  if (!process.env.OPENAI_API_KEY) {
    return fail(
      "OPENAI_API_KEY is not set, so the agent cannot run. Add it to apps/hub/.env and restart. " +
        "Everything else — the wallet, approvals, the relayer — works without it.",
      503,
    );
  }

  try {
    const { text, proposalIds } = await runTurn(parsed.data.text);
    return json({
      text,
      proposalIds,
      proposals: proposalIds.map((id) => listProposals(50).find((p) => p.id === id)).filter(Boolean),
    });
  } catch (err) {
    return fail(err instanceof Error ? err.message : String(err), 500);
  }
}
