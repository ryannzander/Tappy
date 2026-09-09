/**
 * M2 proof: a P-256 signature, produced off-chain exactly the way an iPhone Secure Enclave
 * produces one, executes a real transfer through the deployed gate.
 *
 * The Enclave signs sha256(digest), never the digest itself — CryptoKit hashes its input and
 * offers no way to opt out — so this script signs sha256(digest) too. That is the whole point
 * of the exercise: if this passes, the contract is ready for a real phone.
 *
 * Run: pnpm --filter @flippy/contracts exec tsx script/proveP256.ts
 * Env: SEPOLIA_RPC_URL, AGENT_KEY, RELAYER_KEY
 */
import { readFileSync } from "node:fs";
import { createPublicClient, createWalletClient, http, bytesToHex, hexToBytes, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { sepolia } from "viem/chains";
import { p256 } from "@noble/curves/nist.js";
import { sha256 } from "@noble/hashes/sha2.js";
import { proposalDigest } from "@flippy/protocol";
import { FlippyGateAbi } from "../src-ts/index.js";

function required(name: string): string {
  const v = process.env[name];
  // A half-configured run that fails three steps later with a chain error teaches nothing.
  if (!v) throw new Error(`${name} is not set. Required: SEPOLIA_RPC_URL, AGENT_KEY, RELAYER_KEY.`);
  return v;
}

const rpc = required("SEPOLIA_RPC_URL");
const deployment = JSON.parse(readFileSync(new URL("../deployments/sepolia.json", import.meta.url), "utf8"));
const vector = JSON.parse(readFileSync(new URL("../../protocol/vectors/p256.json", import.meta.url), "utf8"));

if (!deployment.gate) throw new Error("deployments/sepolia.json has no gate address — deploy first.");
if (deployment.humanQx?.toLowerCase() !== vector.qx.toLowerCase()) {
  throw new Error(
    `the deployed gate's humanQx (${deployment.humanQx}) is not the vector's key (${vector.qx}). ` +
      `Redeploy with HUMAN_QX/HUMAN_QY from vectors/p256.json, or sign with the deployed key.`,
  );
}

const agent = privateKeyToAccount(required("AGENT_KEY") as Hex);
const relayer = privateKeyToAccount(required("RELAYER_KEY") as Hex);
const pub = createPublicClient({ chain: sepolia, transport: http(rpc) });
const wallet = createWalletClient({ account: relayer, chain: sepolia, transport: http(rpc) });

const nonce = (await pub.readContract({
  address: deployment.gate,
  abi: FlippyGateAbi,
  functionName: "nonce",
})) as bigint;

// One wei to the agent: the smallest call that proves the gate opened.
const call = { to: agent.address, value: 1n, data: "0x" as Hex };
const deadline = Math.floor(Date.now() / 1000) + 600;

const digest = proposalDigest({ chainId: sepolia.id, gate: deployment.gate, nonce, call, deadline });
const agentSig = await agent.sign({ hash: digest });

// prehash:false is load-bearing. @noble/curves v2 defaults to prehash:true and would hash this
// a second time, producing a signature that verifies locally and is rejected on-chain — a
// self-consistent bug that passes its own self-check. See docs/spikes.md #5.
const message = sha256(hexToBytes(digest));
const humanSig = bytesToHex(p256.sign(message, hexToBytes(vector.privateKey), { prehash: false }));

if (!p256.verify(hexToBytes(humanSig), message, p256.getPublicKey(hexToBytes(vector.privateKey), false), { prehash: false })) {
  throw new Error("the signature does not verify locally — do not waste a transaction on it");
}

console.log("gate    ", deployment.gate);
console.log("nonce   ", nonce);
console.log("digest  ", digest);
console.log("humanSig", humanSig, `(${hexToBytes(humanSig).length} bytes)`);

const hash = await wallet.writeContract({
  address: deployment.gate,
  abi: FlippyGateAbi,
  functionName: "execute",
  args: [call.to, call.value, call.data, BigInt(deadline), agentSig, humanSig],
});
console.log("submitted", hash);

const receipt = await pub.waitForTransactionReceipt({ hash });
console.log("status   ", receipt.status);
console.log("explorer  https://sepolia.etherscan.io/tx/" + hash);
if (receipt.status !== "success") throw new Error("execute() reverted — the gate rejected it");
