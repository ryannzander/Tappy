#!/usr/bin/env bash
# One command that answers "does the Flipper channel work?" — for whoever is holding the device.
#
# It finds the port, installs the app, and runs spike 1: can the laptop write a file over the
# USB CLI while a JS app is running in the foreground? That question has been open since day one
# and the entire bridge-to-device channel depends on it.
#
#   ./scripts/flipper-check.sh
#
# Paste the whole output back, including failures. A failure that names itself is worth more
# than a success nobody can reproduce.
set -uo pipefail
cd "$(dirname "$0")/.."

echo "── 1. finding the Flipper ─────────────────────────────"
PORT="${FLIPPER_PORT:-$(ls /dev/cu.usbmodemflip_* 2>/dev/null | head -1)}"
if [ -z "$PORT" ]; then
  echo "   NOT FOUND. Plug the Flipper in by USB and unlock it."
  echo "   All serial devices currently present:"
  ls /dev/cu.* 2>/dev/null | sed 's/^/     /'
  echo
  echo "   If one of those is clearly the Flipper, re-run as:"
  echo "     FLIPPER_PORT=/dev/cu.thatone ./scripts/flipper-check.sh"
  exit 1
fi
echo "   port: $PORT"

echo
echo "── 2. is the CLI responding? ──────────────────────────"
# The Flipper's CLI speaks over the USB serial port; `info device` is harmless and chatty.
printf 'info device\r\n' > "$PORT" 2>/dev/null &
sleep 1
timeout_read() { perl -e 'alarm 3; exec @ARGV' "$@" 2>/dev/null; }
timeout_read head -c 400 "$PORT" | sed 's/^/     /' || echo "     (no reply — see note below)"

echo
echo "── 3. installing tappy.js ─────────────────────────────"
export FLIPPER_PORT="$PORT"
if pnpm --filter @tappy/bridge exec tsx src/installApp.ts 2>&1 | sed 's/^/     /'; then
  echo "   installed"
else
  echo "   INSTALL FAILED — paste the lines above"
  exit 1
fi

echo
echo "── 4. SPIKE 1 ─────────────────────────────────────────"
echo "   On the Flipper now: Apps -> Scripts -> tappy.js"
echo "   It should print: 'Tappy: waiting for approval requests...'"
echo "   Leave it running and in the foreground."
read -r -p "   Press Enter once it is running... " _

echo "   writing a test request over the CLI while the app is in the foreground..."
pnpm --filter @tappy/bridge exec tsx src/spikeWrite.ts 2>&1 | sed 's/^/     /'

echo
echo "── 5. NFC: does tapping a tag work? ───────────────────"
echo "   This is the headline interaction, and it needs no Apple account:"
echo "   the Flipper reads the tag, the phone never does."
pnpm --filter @tappy/bridge exec tsx src/nfcProbe.ts 2>&1 | sed 's/^/     /'

echo
echo "── verdict ────────────────────────────────────────────"
echo "   If the Flipper showed an approval dialog: THE CHANNEL WORKS."
echo "   If nothing happened: spike 1 has failed and the channel needs the fallback."
echo "   Either way, paste this whole output back."
