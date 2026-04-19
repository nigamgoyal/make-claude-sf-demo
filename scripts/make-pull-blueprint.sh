#!/usr/bin/env bash
# Pull the current scenario blueprint from Make.com, redact credentials, and
# save to blueprints/lead_triage_v1.json in the repo. Idempotent.
#
# Usage:
#   ./scripts/make-pull-blueprint.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

OUTFILE="$REPO_ROOT/blueprints/lead_triage_v1.json"
TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

echo "Pulling blueprint for scenario ${MAKE_SCENARIO_ID}…"
make_api GET "/scenarios/${MAKE_SCENARIO_ID}/blueprint" > "$TMPFILE"

python3 - "$TMPFILE" "$OUTFILE" <<'PY'
import json, re, sys

raw_path, out_path = sys.argv[1], sys.argv[2]
with open(raw_path) as f:
    data = json.load(f)

# Extract the blueprint from the API wrapper
bp = data["response"]["blueprint"]

def redact(obj):
    if isinstance(obj, dict):
        new = {}
        for k, v in obj.items():
            # Redact connection IDs
            if k == "__IMTCONN__" and isinstance(v, (int, str)):
                new[k] = 0
            # Redact connection labels that contain org URL + user name
            elif k == "label" and isinstance(v, str) and "My Salesforce connection" in v:
                new[k] = "<SF_CONNECTION>"
            elif k == "label" and isinstance(v, str) and "My Anthropic Claude connection" in v:
                new[k] = "<ANTHROPIC_CONNECTION>"
            else:
                new[k] = redact(v)
        return new
    if isinstance(obj, list):
        return [redact(x) for x in obj]
    return obj

clean = redact(bp)

with open(out_path, "w") as f:
    json.dump(clean, f, indent=4)
    f.write("\n")

# Final safety check — scan the output for leaks
text = open(out_path).read()
leak_patterns = [
    r"orgfarm-[a-f0-9]+",
    r"Nigam Goyal",
    r"\"__IMTCONN__\":\s*\d{3,}",  # any connection ID >= 3 digits
]
leaks = []
for p in leak_patterns:
    m = re.search(p, text)
    if m:
        leaks.append((p, m.group(0)))

if leaks:
    print("LEAKS FOUND — did not write output:")
    for p, v in leaks:
        print(f"  pattern={p}  matched={v}")
    sys.exit(1)

print(f"Redacted blueprint saved to {out_path}")
print(f"  Modules: {len(clean.get('flow', []))}")
print(f"  Bytes: {len(text)}")
PY
