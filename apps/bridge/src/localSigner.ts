import { createInterface } from "node:readline/promises";
import { privateKeyToAccount } from "viem/accounts";
import type { Address, Hex } from "viem";
import type { Decision, HumanSigner, ProposalView } from "@tappy/protocol";

export interface LocalSignerOptions {
  privateKey: Hex;
  /** false prompts on stdin; true approves everything, for scripted runs only. */
  auto?: boolean;
}

/**
 * The Flipper's stand-in: the same secp256k1 key and the same signature, with the terminal
 * standing in for the device's screen and OK button.
 *
 * Its reason for existing is that it proves everything except the last ten centimetres of USB
 * cable — hub, polling, digest verification, signing, relaying and the on-chain secp256k1 path
 * are all identical. When the hardware arrives, only the prompt changes.
 */
export class LocalHumanSigner implements HumanSigner {
  private readonly account;

  constructor(private readonly opts: LocalSignerOptions) {
    this.account = privateKeyToAccount(opts.privateKey);
  }

  async address(): Promise<Address> {
    return this.account.address;
  }

  async requestApproval(view: ProposalView, _timeoutMs: number): Promise<Decision> {
    console.log(`\n  ┌─ TAPPY ─ approval request ──────────`);
    console.log(`  │ ${view.action}  ${view.amount}`);
    console.log(`  │ to ${view.counterparty}`);
    console.log(`  │ ${view.chain}   ${view.short}`);
    console.log(`  └─────────────────────────────────────`);

    let approved = true;
    if (!this.opts.auto) {
      const rl = createInterface({ input: process.stdin, output: process.stdout });
      const answer = (await rl.question("  approve? [y/N] ")).trim().toLowerCase();
      rl.close();
      approved = answer === "y" || answer === "yes";
    }

    // The digest is the EIP-712 hash; signing it is exactly what signing the typed data does.
    const humanSig = approved ? await this.account.sign({ hash: view.digest }) : undefined;
    return {
      id: view.id,
      approved,
      ...(humanSig ? { humanSig } : {}),
      signer: this.account.address,
      at: Date.now(),
    };
  }
}
