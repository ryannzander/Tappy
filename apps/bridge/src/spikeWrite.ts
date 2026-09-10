/**
 * Spike 1, as a command: write an inbox request over the USB CLI while the JS app holds the
 * foreground, and see whether the app notices.
 *
 * This is the question the whole bridge-to-device channel rests on and it has been open since
 * day one. If it fails, the documented fallbacks are: have the app poll instead of blocking in
 * the dialog (it already does), speak the RPC protobuf protocol instead of the text CLI, or
 * move to a C app that owns USB CDC.
 */
import { loadConfig } from "./config.js";
import { FlipperCli } from "./flipperCli.js";
import { INBOX_PATH } from "@tappy/protocol";

const cfg = loadConfig();
const cli = new FlipperCli(cfg.FLIPPER_PORT, cfg.FLIPPER_BAUD);

await cli.open();
console.log(`opened ${cfg.FLIPPER_PORT}`);

const request = {
  id: "0xspike",
  short: "0xspike…0001",
  action: "SEND",
  amount: "0.010 ETH",
  counterparty: "0xdead…beef",
  chain: "Sepolia",
  seq: Math.floor(Date.now() / 1000),
};

await cli.writeFile(INBOX_PATH, JSON.stringify(request));
console.log(`wrote ${INBOX_PATH}`);
console.log("look at the Flipper — a dialog should be on screen now");

await cli.close();
