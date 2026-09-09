import { formatEther } from "viem";
import { agentAccount, deployment, ethUsd, gateBalanceWei, gateNonce, holdings } from "~/server/tappy/chain";
import { listDevices, listProposals } from "~/server/tappy/store";
import { fail, json } from "~/server/tappy/json";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const d = deployment();
    const [wei, rate, coins] = await Promise.all([gateBalanceWei(), ethUsd(), holdings()]);
    return json({
      gate: d.gate,
      chain: "Sepolia",
      chainId: d.chainId,
      balanceEth: formatEther(wei),
      ethUsd: rate,
      balanceUsd: (Number(formatEther(wei)) * rate).toFixed(2),
      // Everything the wallet holds, not just the native coin.
      holdings: coins,
      totalUsd: coins.reduce((sum, c) => sum + Number(c.usd), 0).toFixed(2),
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
