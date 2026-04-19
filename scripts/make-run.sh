#!/usr/bin/env bash
# Trigger a one-off run of the Lead-triage scenario.
#
# Usage:
#   ./scripts/make-run.sh                   # uses MAKE_SCENARIO_ID from .env
#   ./scripts/make-run.sh <scenario-id>     # override
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

SCENARIO_ID="${1:-$MAKE_SCENARIO_ID}"

echo "Triggering run on scenario ${SCENARIO_ID}…"
make_api POST "/scenarios/${SCENARIO_ID}/run" | pp
