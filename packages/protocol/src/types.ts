import { z } from "zod";
import type { Address, Hex } from "viem";

export const hexSchema = z.custom<Hex>((v) => typeof v === "string" && /^0x[0-9a-fA-F]*$/.test(v));
export const addressSchema = z.custom<Address>(
  (v) => typeof v === "string" && /^0x[0-9a-fA-F]{40}$/.test(v),
);
const bigintish = z.union([z.bigint(), z.string(), z.number()]).transform((v) => BigInt(v));

/** What the agent wants to do, in human terms. Derived from `call`, never the source of truth. */
export const actionSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("send"), to: addressSchema, valueWei: bigintish, memo: z.string().optional() }),
  z.object({
    kind: z.literal("sendToken"),
    token: addressSchema,
    to: addressSchema,
    /** Base units, not a decimal — USDC has 6 decimals and ETH has 18. */
    amount: bigintish,
    symbol: z.string(),
    decimals: z.number(),
    memo: z.string().optional(),
  }),
  z.object({
    kind: z.literal("swap"),
    dex: addressSchema,
    sellWei: bigintish,
    minBuy: bigintish,
    tokenOut: addressSchema,
  }),
]);
export type Action = z.infer<typeof actionSchema>;

export const PROPOSAL_STATUSES = [
  "PENDING_HUMAN",
  "REJECTED",
  "SUBMITTED",
  "EXECUTED",
  "FAILED",
  "EXPIRED",
] as const;
export const proposalStatusSchema = z.enum(PROPOSAL_STATUSES);
export type ProposalStatus = (typeof PROPOSAL_STATUSES)[number];

/** Legal state transitions. Anything else is a bug, not a log line. */
export const ALLOWED_TRANSITIONS: Record<ProposalStatus, ProposalStatus[]> = {
  PENDING_HUMAN: ["REJECTED", "SUBMITTED", "EXPIRED", "FAILED"],
  REJECTED: [],
  SUBMITTED: ["EXECUTED", "FAILED"],
  EXECUTED: [],
  FAILED: [],
  EXPIRED: [],
};

export const callSchema = z.object({
  to: addressSchema,
  value: bigintish,
  data: hexSchema,
});
export type Call = z.infer<typeof callSchema>;

export const proposalSchema = z.object({
  /** The EIP-712 digest. The id IS the hash, so an id is bound to one exact call. */
  id: hexSchema,
  chainId: z.number(),
  gate: addressSchema,
  nonce: bigintish,
  call: callSchema,
  action: actionSchema,
  /** Unix seconds. The contract rejects execution after this. */
  deadline: z.number(),
  agentSig: hexSchema.optional(),
  humanSig: hexSchema.optional(),
  status: proposalStatusSchema,
  txHash: hexSchema.optional(),
  error: z.string().optional(),
  createdAt: z.number(),
  decidedAt: z.number().optional(),
  originator: z.enum(["chat", "test"]),
});
export type Proposal = z.infer<typeof proposalSchema>;

/** Exactly what the Flipper screen renders. Keep it small: 128x64 pixels. */
export const proposalViewSchema = z.object({
  id: hexSchema,
  short: z.string(),
  action: z.enum(["SEND", "SWAP"]),
  amount: z.string(),
  counterparty: z.string(),
  chain: z.string(),
  digest: hexSchema,
});
export type ProposalView = z.infer<typeof proposalViewSchema>;

export const decisionSchema = z.object({
  id: hexSchema,
  approved: z.boolean(),
  humanSig: hexSchema.optional(),
  signer: addressSchema,
  at: z.number(),
});
export type Decision = z.infer<typeof decisionSchema>;

/**
 * The seam that lets two thirds of the team work without touching hardware.
 * MockHumanSigner and FlipperHumanSigner are interchangeable.
 */
export interface HumanSigner {
  address(): Promise<Address>;
  requestApproval(view: ProposalView, timeoutMs: number): Promise<Decision>;
}

/* ---- Approval channel (hub <-> signer process) ---------------------------- */

export const signerKindSchema = z.enum(["mock", "flipper", "flipper-c"]);
export type SignerKind = z.infer<typeof signerKindSchema>;

export const signerHelloSchema = z.object({
  t: z.literal("signer.hello"),
  address: addressSchema,
  kind: signerKindSchema,
});
export const approvalRequestSchema = z.object({
  t: z.literal("approval.request"),
  view: proposalViewSchema,
  timeoutMs: z.number(),
});
export const approvalResultSchema = z.object({
  t: z.literal("approval.result"),
  decision: decisionSchema,
});
export const approvalCancelSchema = z.object({ t: z.literal("approval.cancel"), id: hexSchema });

export const signerToHubSchema = z.discriminatedUnion("t", [signerHelloSchema, approvalResultSchema]);
export const hubToSignerSchema = z.discriminatedUnion("t", [approvalRequestSchema, approvalCancelSchema]);
export type SignerToHub = z.infer<typeof signerToHubSchema>;
export type HubToSigner = z.infer<typeof hubToSignerSchema>;

/* ---- Flipper file protocol (bridge <-> tappy.js) ------------------------- */

export const INBOX_PATH = "/ext/apps_data/tappy/inbox.json";
export const OUTBOX_PATH = "/ext/apps_data/tappy/outbox.json";

export const flipperRequestSchema = proposalViewSchema
  .omit({ digest: true })
  .extend({ seq: z.number() });
export type FlipperRequest = z.infer<typeof flipperRequestSchema>;

export const flipperResponseSchema = z.object({
  id: hexSchema,
  seq: z.number(),
  approved: z.boolean(),
  at: z.number(),
});
export type FlipperResponse = z.infer<typeof flipperResponseSchema>;

/* ---- The iOS surface ------------------------------------------------------ */

export const humanKeyKindSchema = z.enum(["p256-enclave", "p256-software", "secp256k1"]);
export type HumanKeyKind = z.infer<typeof humanKeyKindSchema>;

/**
 * Everything the phone needs to independently verify a proposal and render it.
 * Deliberately carries the raw call: the phone recomputes the digest rather than
 * trusting the id the hub sent. Deliberately omits agentSig — the phone has no use
 * for it, and a signature it does not need is a signature it cannot leak.
 */
export const mobileProposalSchema = z.object({
  id: hexSchema,
  chainId: z.number(),
  gate: addressSchema,
  nonce: bigintish,
  call: callSchema,
  action: actionSchema,
  deadline: z.number(),
  status: proposalStatusSchema,
  txHash: hexSchema.optional(),
  error: z.string().optional(),
});
export type MobileProposal = z.infer<typeof mobileProposalSchema>;

/** A registered approval device. `publicKey` is 64 bytes qx‖qy for P-256, a 20-byte address for secp256k1. */
export const deviceSchema = z.object({
  id: z.string(),
  kind: humanKeyKindSchema,
  publicKey: hexSchema,
  label: z.string(),
  registeredAt: z.number(),
});
export type Device = z.infer<typeof deviceSchema>;

/** A physical NFC token the hub recognises. The tag is a trigger, not a secret. */
export const stationSchema = z.object({
  stationId: z.string(),
  label: z.string(),
  tagUid: hexSchema.optional(),
});
export type Station = z.infer<typeof stationSchema>;
