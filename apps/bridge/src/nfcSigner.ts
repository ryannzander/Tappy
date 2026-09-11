import { privateKeyToAccount } from "viem/accounts";
import type { Address, Hex } from "viem";
import type { Decision, HumanSigner, ProposalView } from "@tappy/protocol";
import type { FlipperCli } from "./flipperCli.js";

export interface NfcSignerOptions {
  privateKey: Hex;
  cli: FlipperCli;
  /** UIDs allowed to approve, lowercase hex without separators. Empty means any tag. */
  allowedUids?: string[];
  /** How long a human gets to find the tag before the proposal is left pending. */
  timeoutMs?: number;
  /** Overridable because the CLI's NFC verb differs across firmware. */
  command?: string;
}

/**
 * Approval by tapping an NFC tag on the Flipper.
 *
 * The Flipper reads the tag, not the phone — which is the whole reason this works without an
 * Apple Developer account. Core NFC needs a paid entitlement; the Flipper needs a USB cable.
 * And because the laptop drives the read over the CLI, there is no app to write on the device:
 * no C app, and no need for an NFC module in the JS engine, which does not have one.
 *
 * What the tap proves is physical presence, not identity. A tag's UID is readable and cloneable
 * by anyone who can hold a reader near it — so this is "something you have", standing in the
 * same place a button press would, not a secret. The signing key never leaves the laptop in v1.
 * Say that plainly rather than implying the tag is a credential.
 */
export class NfcHumanSigner implements HumanSigner {
  private readonly account;

  constructor(private readonly opts: NfcSignerOptions) {
    this.account = privateKeyToAccount(opts.privateKey);
  }

  async address(): Promise<Address> {
    return this.account.address;
  }

  async requestApproval(view: ProposalView, timeoutMs: number): Promise<Decision> {
    const limit = this.opts.timeoutMs ?? timeoutMs;

    console.log(`\n  ┌─ TAPPY ─ approval request ──────────`);
    console.log(`  │ ${view.action}  ${view.amount}`);
    console.log(`  │ to ${view.counterparty}`);
    console.log(`  │ ${view.chain}   ${view.short}`);
    console.log(`  └─────────────────────────────────────`);
    console.log(`  TAP THE TAG ON THE FLIPPER TO APPROVE  (${Math.round(limit / 1000)}s)\n`);

    const uid = await this.waitForTap(limit);

    if (!uid) {
      console.log("  no tag — left pending, nothing signed");
      return { id: view.id, approved: false, signer: this.account.address, at: Date.now() };
    }

    const allowed = this.opts.allowedUids ?? [];
    if (allowed.length > 0 && !allowed.includes(uid)) {
      // A tag we do not know is a decline, not an error. Someone tapped the wrong thing.
      console.log(`  tag ${uid} is not registered — declining`);
      return { id: view.id, approved: false, signer: this.account.address, at: Date.now() };
    }

    console.log(`  tag ${uid} — approving`);
    // The digest is the EIP-712 hash; signing it is exactly what signing the typed data does.
    const humanSig = await this.account.sign({ hash: view.digest });
    return { id: view.id, approved: true, humanSig, signer: this.account.address, at: Date.now() };
  }

  /**
   * Runs the Flipper's NFC read and waits for a UID to appear in its output.
   *
   * Firmware versions disagree about the verb and about how they print a UID, so this matches
   * loosely — several hex bytes on a line that mentions UID — and the exact command is
   * overridable. `scripts/flipper-check.sh` prints the real `nfc` help from the device, which
   * is the ground truth if this needs adjusting.
   */
  private async waitForTap(timeoutMs: number): Promise<string | null> {
    const { cli } = this.opts;
    const command = this.opts.command ?? "nfc detect";

    cli.clearTranscript();
    cli.send(command);

    try {
      const match = await cli.awaitMatch(
        /UID[^\n]*?((?:[0-9A-Fa-f]{2}[\s:-]?){4,10})/,
        timeoutMs,
      );
      const uid = (match[1] ?? "").replace(/[^0-9A-Fa-f]/g, "").toLowerCase();
      return uid.length >= 8 ? uid : null;
    } catch {
      return null;
    } finally {
      // The read streams until stopped; leaving it running would eat the next command.
      cli.interrupt();
    }
  }
}
