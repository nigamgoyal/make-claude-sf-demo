#!/usr/bin/env bash
# Show scenario metadata (name, active state, last edit).
#
# Usage:
#   ./scripts/make-status.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

echo "Scenario ${MAKE_SCENARIO_ID} status…"
make_api GET "/scenarios/${MAKE_SCENARIO_ID}" | pp
