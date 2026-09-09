import { formatEther } from "viem";
import { agentAccount, deployment, gateBalanceWei, gateNonce } from "~/server/flippy/chain";
import { listDevices, listProposals } from "~/server/flippy/store";
import { fail, json } from "~/server/flippy/json";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const d = deployment();
    return json({
      gate: d.gate,
      chain: "Sepolia",
      chainId: d.chainId,
      balanceEth: formatEther(await gateBalanceWei()),
      nonce: await gateNonce(),
      agent: agentAccount().address,
      humanQx: d.humanQx,
      humanQy: d.humanQy,
      devices: listDevices(),
      proposals: listProposals(10),
    });
  } catch (err) {
    return fail(err instanceof Error ? err.message : String(err), 500);
  }
}
