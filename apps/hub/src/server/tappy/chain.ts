import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  createPublicClient,
  createWalletClient,
  http,
  hexToBytes,
  recoverAddress,
  zeroAddress,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { sepolia } from "viem/chains";
import { p256 } from "@noble/curves/nist.js";
import { sha256 } from "@noble/hashes/sha2.js";
import { proposalDigest, type Call } from "@tappy/protocol";
import { TappyGateAbi } from "@tappy/contracts";

function required(name: string): string {
  const v = process.env[name];
  // Half-configured is worse than unconfigured: it fails later, on stage, as a chain error.
  if (!v) throw new Error(`${name} is not set. See .env.example.`);
  return v;
}

export interface Deployment {
  chainId: number;
  gate: Address;
  token: Address;
  swap: Address;
  agent: Address;
  humanK1: Address;
  humanQx: Hex;
  humanQy: Hex;
  p256Verifier: Address;
}

let cached: Deployment | undefined;

export function deployment(): Deployment {
  if (cached) return cached;

  // Resolved from cwd, not import.meta.url: webpack rewrites module URLs, so an import.meta
  // path silently points somewhere that does not exist once this is bundled. Next runs with
  // cwd at apps/hub, but tolerate being invoked from the repo root too.
  const candidates = [
    resolve(process.cwd(), "../../packages/contracts/deployments/sepolia.json"),
    resolve(process.cwd(), "packages/contracts/deployments/sepolia.json"),
  ];

  for (const path of candidates) {
    try {
      cached = JSON.parse(readFileSync(path, "utf8")) as Deployment;
      return cached;
    } catch {
      // try the next one
    }
  }

  throw new Error(
    `Could not read the deployment. Looked in:\n  ${candidates.join("\n  ")}\n` +
      "Deploy the gate first:\n" +
      "  cd packages/contracts && forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast",
  );
}

export const publicClient = () =>
  createPublicClient({ chain: sepolia, transport: http(required("SEPOLIA_RPC_URL")) });

export const agentAccount = () => privateKeyToAccount(required("AGENT_KEY") as Hex);

const relayerClient = () =>
  createWalletClient({
    account: privateKeyToAccount(required("RELAYER_KEY") as Hex),
    chain: sepolia,
    transport: http(required("SEPOLIA_RPC_URL")),
  });

export async function gateNonce(): Promise<bigint> {
  return (await publicClient().readContract({
    address: deployment().gate,
    abi: TappyGateAbi,
    functionName: "nonce",
  })) as bigint;
}

export async function gateBalanceWei(): Promise<bigint> {
  return publicClient().getBalance({ address: deployment().gate });
}

/** The agent half of the 2-of-2. Never sees the human key; never can. */
export async function signAsAgent(digest: Hex): Promise<Hex> {
  return agentAccount().sign({ hash: digest });
}

/**
 * Checks the human's signature before we spend gas on it. The chain would reject a bad one
 * anyway, but it would cost a transaction and report only "BadHumanSig", which says nothing
 * about why. Failing here gives us the reason in a log line.
 *
 * Signature length is the discriminator, exactly as it is in TappyGate: 65 bytes is the
 * Flipper's secp256k1, 64 is the iPhone's Secure Enclave P-256. One gate, two devices.
 */
export async function verifyHumanSignature(digest: Hex, signature: Hex): Promise<"secp256k1" | "p256" | false> {
  const d = deployment();
  const bytes = hexToBytes(signature);

  if (bytes.length === 65) {
    if (!d.humanK1 || d.humanK1 === zeroAddress) return false;
    const recovered = await recoverAddress({ hash: digest, signature });
    return recovered.toLowerCase() === d.humanK1.toLowerCase() ? "secp256k1" : false;
  }

  if (bytes.length !== 64) return false;
  if (!d.humanQx || /^0x0*$/.test(d.humanQx)) return false;

  // The Secure Enclave signs sha256(digest) — CryptoKit hashes its input and offers no way
  // to opt out — and prehash:false stops @noble/curves v2 hashing it a second time.
  const message = sha256(hexToBytes(digest));
  const pubkey = new Uint8Array(65);
  pubkey[0] = 0x04;
  pubkey.set(hexToBytes(d.humanQx), 1);
  pubkey.set(hexToBytes(d.humanQy), 33);
  try {
    return p256.verify(bytes, message, pubkey, { prehash: false, lowS: false }) ? "p256" : false;
  } catch {
    return false;
  }
}

export function digestFor(nonce: bigint, call: Call, deadline: number): Hex {
  return proposalDigest({ chainId: sepolia.id, gate: deployment().gate, nonce, call, deadline });
}

/** Relays the 2-of-2 to the chain. The relayer only pays gas; it has no authority. */
export async function relayExecute(
  call: Call,
  deadline: number,
  agentSig: Hex,
  humanSig: Hex,
): Promise<Hex> {
  return relayerClient().writeContract({
    address: deployment().gate,
    abi: TappyGateAbi,
    functionName: "execute",
    args: [call.to, call.value, call.data, BigInt(deadline), agentSig, humanSig],
  });
}

/**
 * Sepolia ETH is worthless, but the demo reads better in dollars than in four decimal places
 * of a testnet coin. Priced off real mainnet ETH so the numbers feel like money.
 *
 * Cached for a minute and falls back to a fixed rate: a price feed hiccup should never be the
 * thing that breaks a demo, and the exact number does not matter to anything but the display.
 */
const FALLBACK_ETH_USD = 3000;
let priceCache: { usd: number; at: number } | undefined;

export async function ethUsd(): Promise<number> {
  if (priceCache && Date.now() - priceCache.at < 60_000) return priceCache.usd;
  try {
    const res = await fetch("https://api.coinbase.com/v2/prices/ETH-USD/spot", {
      signal: AbortSignal.timeout(3000),
    });
    const body = (await res.json()) as { data?: { amount?: string } };
    const usd = Number(body.data?.amount);
    if (!Number.isFinite(usd) || usd <= 0) throw new Error("bad price payload");
    priceCache = { usd, at: Date.now() };
    return usd;
  } catch {
    return priceCache?.usd ?? FALLBACK_ETH_USD;
  }
}

export const explorerTx = (hash: string) => `https://sepolia.etherscan.io/tx/${hash}`;
