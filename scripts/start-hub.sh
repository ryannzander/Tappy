#!/usr/bin/env bash
# Starts the hub detached, so it survives the shell that launched it.
#
# Background jobs started from a shell die with their parent; nohup plus disown orphans the
# process to init instead. Logs to /tmp/tappy-hub.log.
#
# Keys come from the repo-root .env, never from defaults baked in here. These are testnet keys
# and the repo checks them in on purpose (CLAUDE.md), but a default in a script is silently
# wrong in a way a missing variable is not: you cannot tell whether you are running with your
# own key or one that shipped with the repo.
set -euo pipefail
cd "$(dirname "$0")/.."

# Load .env without clobbering anything already exported. A blank line in .env used to
# overwrite a value passed on the command line, which then failed the check below and left
# the old server running — a confusing way to discover your restart did nothing.
if [ -f .env ]; then
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    key=${line%%=*}
    value=${line#*=}
    [ "$key" = "$line" ] && continue
    # Existing environment wins, and an empty value in .env is not a value.
    [ -n "${!key:-}" ] && continue
    [ -z "$value" ] && continue
    export "$key=$(printf '%s' "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
  done < .env
fi

: "${SEPOLIA_RPC_URL:?not set. Add it to .env — see .env.example}"
: "${AGENT_KEY:?not set. Add it to .env — see .env.example}"
: "${RELAYER_KEY:?not set. Add it to .env — see .env.example}"
export SEPOLIA_RPC_URL AGENT_KEY RELAYER_KEY

pkill -f "next dev -p 3100" 2>/dev/null || true
sleep 1

nohup pnpm --filter @tappy/hub exec next dev -p 3100 > /tmp/tappy-hub.log 2>&1 &
disown
echo "hub starting (pid $!), log: /tmp/tappy-hub.log"
