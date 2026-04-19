#!/usr/bin/env bash
# Shared helpers sourced by the other scripts in this directory.
# Loads .env from the repo root and validates required vars.

# Find repo root (parent of scripts/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found at $ENV_FILE" >&2
  echo "Copy .env.example to .env and fill in your values." >&2
  exit 1
fi

# Load .env (ignoring commented lines and empty ones)
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# Validate required vars
for var in MAKE_API_TOKEN MAKE_ZONE MAKE_TEAM_ID MAKE_SCENARIO_ID; do
  if [[ -z "${!var}" ]]; then
    echo "ERROR: $var is not set in .env" >&2
    exit 1
  fi
done

MAKE_API_BASE="https://${MAKE_ZONE}/api/v2"

# Wrapper that hits the Make API with auth + common headers
make_api() {
  local method="$1"
  local path="$2"
  shift 2
  curl -sS -X "$method" \
    -H "Authorization: Token ${MAKE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "${MAKE_API_BASE}${path}" \
    "$@"
}

# Pretty-print JSON if jq is available, else raw
pp() {
  if command -v jq >/dev/null 2>&1; then
    jq .
  else
    cat
  fi
}
