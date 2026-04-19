#!/usr/bin/env bash
# List incomplete executions for the scenario.
#
# Usage:
#   ./scripts/make-incomplete.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

echo "Incomplete executions for scenario ${MAKE_SCENARIO_ID}…"
make_api GET "/dlqs?scenarioId=${MAKE_SCENARIO_ID}&teamId=${MAKE_TEAM_ID}" | pp
