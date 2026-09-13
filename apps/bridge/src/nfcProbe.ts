/**
 * Learns how this Flipper's NFC CLI actually behaves, then waits for one tap.
 *
 * The verb and the output format differ across firmware versions and forks, and guessing wrong
 * wastes the time of whoever is holding the device. This asks the device instead: it prints the
 * `nfc` help, runs a read, and dumps the raw bytes that come back when a tag is tapped.
 *
 *   pnpm --filter @tappy/bridge nfc:probe
 *
 * Paste the whole output back. The UID line is what the signer matches on.
 */
import { loadConfig } from "./config.js";
import { FlipperCli } from "./flipperCli.js";

const cfg = loadConfig();
const cli = new FlipperCli(cfg.FLIPPER_PORT, cfg.FLIPPER_BAUD);
await cli.open();
console.log(`connected on ${cfg.FLIPPER_PORT}\n`);

console.log("── what NFC commands does this firmware have? ──");
for (const probe of ["nfc ?", "nfc help", "nfc"]) {
  cli.clearTranscript();
  const out = await cli.command(probe, 3000).catch(() => "");
  if (out.trim()) {
    console.log(`$ ${probe}`);
    console.log(out.trim().split("\n").map((l) => "   " + l).join("\n"));
    break;
  }
}

console.log(`\n── running "${cfg.FLIPPER_NFC_CMD}" — TAP A TAG ON THE FLIPPER NOW ──`);
cli.clearTranscript();
cli.send(cfg.FLIPPER_NFC_CMD);

try {
  const match = await cli.awaitMatch(/UID[^\n]*?((?:[0-9A-Fa-f]{2}[\s:-]?){4,10})/, 30000);
  const uid = (match[1] ?? "").replace(/[^0-9A-Fa-f]/g, "").toLowerCase();
  console.log(`\n   TAG READ. uid = ${uid}`);
  console.log(`   Put this in .env to restrict approvals to it:`);
  console.log(`     ALLOWED_UIDS=${uid}`);
} catch {
  console.log("\n   No UID matched in 30s. Raw output follows — the UID is probably in here");
  console.log("   under a different label, and the signer's pattern needs adjusting:");
  console.log(cli.transcript.split("\n").map((l) => "   | " + l).join("\n"));
} finally {
  cli.interrupt();
  await cli.close();
}
