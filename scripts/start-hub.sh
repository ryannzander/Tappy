#!/usr/bin/env bash
# Starts the hub detached, so it survives the shell that launched it.
#
# Background jobs started from a tool call die with their parent; nohup + disown orphans the
# process to init instead. Logs to /tmp/tappy-hub.log.
set -euo pipefail
cd "$(dirname "$0")/.."

export SEPOLIA_RPC_URL="${SEPOLIA_RPC_URL:-https://ethereum-sepolia-rpc.publicnode.com}"
export AGENT_KEY="${AGENT_KEY:-0x1b64cb93665e42892acdf228ac890959865669ea1690974677e07c8e5d727843}"
export RELAYER_KEY="${RELAYER_KEY:-0x4ed1eb1603bca765314bf39978c3373229259e16d35ca8aa14b8e96bcf33afdc}"

pkill -f "next dev -p 3100" 2>/dev/null || true
sleep 1

nohup pnpm --filter @tappy/hub exec next dev -p 3100 > /tmp/tappy-hub.log 2>&1 &
disown
echo "hub starting (pid $!), log: /tmp/tappy-hub.log"
