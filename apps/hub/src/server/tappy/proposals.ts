import { encodeFunctionData, parseEther, type Address, type Hex } from "viem";
import { sepolia } from "viem/chains";
import type { Action, Call, Proposal } from "@tappy/protocol";
import { MockSwapAbi } from "@tappy/contracts";
import { deployment, digestFor, gateNonce, signAsAgent } from "./chain.js";
import { putProposal } from "./store.js";

/** Ten minutes is long enough to pick up a phone and short enough that a stale proposal dies. */
const TTL_SECONDS = 600;

/** Turns an intent into the exact call the chain will make, then has the agent sign it. */
export async function createProposal(action: Action): Promise<Proposal> {
  const d = deployment();
  const call = callFor(action, d.swap);
  const nonce = await gateNonce();
  const deadline = Math.floor(Date.now() / 1000) + TTL_SECONDS;
  const id = digestFor(nonce, call, deadline);

  const proposal: Proposal = {
    id,
    chainId: sepolia.id,
    gate: d.gate,
    nonce,
    call,
    action,
    deadline,
    agentSig: await signAsAgent(id),
    status: "PENDING_HUMAN",
    createdAt: Date.now(),
    originator: "chat",
  };
  putProposal(proposal);
  return proposal;
}

function callFor(action: Action, swap: Address): Call {
  switch (action.kind) {
    case "send":
      return { to: action.to, value: action.valueWei, data: "0x" };
    case "swap":
      return {
        to: swap,
        value: action.sellWei,
        data: encodeFunctionData({
          abi: MockSwapAbi,
          functionName: "swapExactEthForTokens",
          args: [action.minBuy],
        }) as Hex,
      };
  }
}

export function sendAction(to: Address, amountEth: string, memo?: string): Action {
  return { kind: "send", to, valueWei: parseEther(amountEth), ...(memo ? { memo } : {}) };
}

export function swapAction(amountEth: string): Action {
  const d = deployment();
  // minBuy 0: this is a mock DEX at a fixed rate on a testnet, and slippage protection
  // would be theatre. A real one would quote and apply a tolerance here.
  return { kind: "swap", dex: d.swap, sellWei: parseEther(amountEth), minBuy: 0n, tokenOut: d.token };
}
