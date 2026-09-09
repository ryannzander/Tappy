import { randomUUID } from "node:crypto";
import { deviceSchema, humanKeyKindSchema, hexSchema } from "@flippy/protocol";
import { z } from "zod";
import { putDevice } from "~/server/flippy/store";
import { deployment } from "~/server/flippy/chain";
import { fail, json } from "~/server/flippy/json";

export const dynamic = "force-dynamic";

const bodySchema = z.object({
  kind: humanKeyKindSchema,
  publicKey: hexSchema,
  label: z.string().min(1),
});

export async function POST(req: Request) {
  const parsed = bodySchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return fail("expected { kind, publicKey, label }");

  const device = deviceSchema.parse({
    id: randomUUID(),
    ...parsed.data,
    registeredAt: Date.now(),
  });
  putDevice(device);

  // The gate's human key is fixed at deploy time. If the phone registers a different one,
  // every approval it signs will be rejected on-chain — say so now, not after a failed tx.
  const d = deployment();
  const onChain = (d.humanQx + d.humanQy.slice(2)).toLowerCase();
  const matchesGate = device.publicKey.toLowerCase() === onChain;

  return json({
    deviceId: device.id,
    matchesGate,
    gateHumanKey: onChain,
    warning: matchesGate
      ? undefined
      : "This device's key is NOT the one the deployed gate accepts. Redeploy the gate with " +
        "HUMAN_QX/HUMAN_QY set to this key, or approvals will revert with BadHumanSig.",
  });
}
