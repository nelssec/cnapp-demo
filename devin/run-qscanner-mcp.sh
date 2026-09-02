#!/usr/bin/env bash
# Launches the QScanner MCP server for Devin. Used as the `command` in devin/mcp-config.json.
# - Finds the repo root relative to this script, so the checkout path does not matter.
# - Downloads the release binary into .qscanner/ on first use (needs gh auth or GH_TOKEN).
# - Reads QUALYS_ACCESS_TOKEN / QUALYS_IAC_USERNAME / QUALYS_IAC_PASSWORD from the environment
#   (Devin secrets are exported into the VM environment). Never prints them.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/.qscanner/qscanner"
if [[ ! -x "$BIN" ]]; then
  echo "qscanner binary missing; downloading release into $ROOT/.qscanner" >&2
  "$ROOT/scripts/get-qscanner.sh" "$ROOT/.qscanner" >/dev/null || { echo "download failed: authenticate gh (gh auth login) or set GH_TOKEN with read access to nelssec/cnapp-demo" >&2; exit 1; }
fi
[[ -n "${QUALYS_ACCESS_TOKEN:-}" ]] || echo "warning: QUALYS_ACCESS_TOKEN is not set; scans that need the Qualys backend will fail" >&2
export QUALYS_IAC_AUTH_TYPE="${QUALYS_IAC_AUTH_TYPE:-basic}"
exec "$BIN" mcp --pod "${QUALYS_POD:-CA1}"
