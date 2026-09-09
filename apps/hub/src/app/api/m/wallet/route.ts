import { formatEther } from "viem";
import { agentAccount, deployment, ethUsd, gateBalanceWei, gateNonce } from "~/server/flippy/chain";
import { listDevices, listProposals } from "~/server/flippy/store";
import { fail, json } from "~/server/flippy/json";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const d = deployment();
    const [wei, rate] = await Promise.all([gateBalanceWei(), ethUsd()]);
    return json({
      gate: d.gate,
      chain: "Sepolia",
      chainId: d.chainId,
      balanceEth: formatEther(wei),
      ethUsd: rate,
      balanceUsd: (Number(formatEther(wei)) * rate).toFixed(2),
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
