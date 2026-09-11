import { z } from "zod";

const schema = z.object({
  HUMAN_KEY: z.string().regex(/^0x[0-9a-fA-F]{64}$/, "HUMAN_KEY must be a 32-byte hex key"),
  HUB_URL: z.string().url().default("http://localhost:3100"),
  // The Flipper names its serial port after itself: /dev/cu.usbmodemflip_<DeviceName>1.
  // Find yours with: ls /dev/cu.usbmodemflip_*
  FLIPPER_PORT: z.string().default("/dev/cu.usbmodemflip_Tappy1"),
  FLIPPER_BAUD: z.coerce.number().default(230400),
  // flipper: the real device. local: this terminal stands in for it, same key and signature.
  // auto: same again but approves without asking, for scripted runs. mock: the protocol's
  // MockHumanSigner, which only signs messages it was told about.
  // nfc: tap a tag on the Flipper to approve — the headline interaction, and it needs no
  // Apple Developer account because the Flipper reads the tag, not the phone.
  // flipper: the device's own screen and buttons. local: this terminal stands in, same key and
  // signature. auto: same again without asking, for scripted runs. mock: the protocol's
  // MockHumanSigner, which only signs messages it was told about.
  SIGNER_KIND: z.enum(["nfc", "flipper", "local", "auto", "mock"]).default("nfc"),
  /** Comma-separated tag UIDs allowed to approve. Empty means any tag. */
  ALLOWED_UIDS: z.string().default(""),
  /** The CLI verb that starts an NFC read. Differs across firmware; see flipper-check.sh. */
  FLIPPER_NFC_CMD: z.string().default("nfc detect"),
  CHAIN_KEY: z.enum(["sepolia", "arc", "hedera"]).default("sepolia"),
  GATE_ADDRESS: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
});

export type Config = z.infer<typeof schema>;

export function loadConfig(): Config {
  const parsed = schema.safeParse(process.env);
  if (!parsed.success) {
    console.error("Bad bridge config. Copy .env.example to .env and fill it in:");
    console.error(parsed.error.flatten().fieldErrors);
    process.exit(1);
  }
  return parsed.data;
}
