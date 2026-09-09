import { describe, expect, it } from "vitest";
import { mobileProposalSchema, deviceSchema, stationSchema, toMobileProposal } from "../src/index.js";
import type { Proposal } from "../src/index.js";

const proposal: Proposal = {
  id: "0xc56ce0a94d4eca26131f5503a69d659d1aea43e8bb835943e0a463719f6862ad",
  chainId: 11155111,
  gate: "0x1111111111111111111111111111111111111111",
  nonce: 0n,
  call: { to: "0x2222222222222222222222222222222222222222", value: 10000000000000000n, data: "0x" },
  action: { kind: "send", to: "0x2222222222222222222222222222222222222222", valueWei: 10000000000000000n },
  deadline: 2000000000,
  status: "PENDING_HUMAN",
  createdAt: 1757280000,
  originator: "chat",
};

describe("mobile schemas", () => {
  it("carries every field the phone needs to recompute the digest", () => {
    const m = toMobileProposal(proposal);
    expect(mobileProposalSchema.parse(m)).toBeTruthy();
    for (const k of ["chainId", "gate", "nonce", "call", "deadline"]) {
      expect(m).toHaveProperty(k);
    }
  });

  it("never leaks the agent signature to the phone", () => {
    expect(toMobileProposal({ ...proposal, agentSig: "0xdead" })).not.toHaveProperty("agentSig");
  });

  it("accepts a P-256 enclave device", () => {
    expect(
      deviceSchema.parse({
        id: "dev_1",
        kind: "p256-enclave",
        publicKey: `0x${"ab".repeat(64)}`,
        label: "Ryan's iPhone",
        registeredAt: 1757280000,
      }),
    ).toBeTruthy();
  });

  it("rejects an unknown key kind", () => {
    expect(() =>
      deviceSchema.parse({
        id: "dev_1",
        kind: "rsa",
        publicKey: "0xab",
        label: "x",
        registeredAt: 1,
      }),
    ).toThrow();
  });

  it("accepts a station whose tag has not been pinned yet", () => {
    expect(stationSchema.parse({ stationId: "desk", label: "Desk puck" })).toBeTruthy();
  });
});
