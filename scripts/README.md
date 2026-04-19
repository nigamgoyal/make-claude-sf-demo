# Scripts

Bash helpers for working with the Make.com scenario from the terminal. All scripts source `.env` at the repo root for credentials and IDs.

## Setup

1. Copy the env template:
   ```bash
   cp ../.env.example ../.env
   ```
2. Edit `../.env` and fill in:
   - `MAKE_API_TOKEN` — from Make.com → profile → API tokens
   - `MAKE_ZONE` — e.g. `us2.make.com`
   - `MAKE_TEAM_ID` — from your URL bar
   - `MAKE_SCENARIO_ID` — the numeric ID of the Lead-triage scenario
3. Make the scripts executable:
   ```bash
   chmod +x scripts/*.sh
   ```

`.env` is gitignored — it never enters the commit history.

## Scripts

### `make-run.sh`

Triggers a one-off run of the scenario.

```bash
./scripts/make-run.sh                 # runs the scenario in MAKE_SCENARIO_ID
./scripts/make-run.sh 4795249         # override with a specific scenario id
```

### `make-status.sh`

Returns the scenario's metadata (name, last-edit timestamp, whether it's active, etc.).

```bash
./scripts/make-status.sh
```

Useful as a quick health check before running the scenario — confirms the token works and the scenario exists.

### `make-incomplete.sh`

Lists bundles that failed and landed in the Incomplete Executions queue.

```bash
./scripts/make-incomplete.sh
```

Useful when verifying that the retry / error-handler logic is surfacing failures correctly. If this returns an empty array, the scenario has no pending failures.

## Why these scripts exist

- **Faster iteration.** Trigger a run from your terminal instead of opening the Make UI, scrolling, clicking "Run once."
- **Scriptable smoke tests.** You can chain with `sf` CLI calls to automate: create Lead → run scenario → query summary field.
- **Auditable.** Scripts are in git; the only secret (token) lives in a local `.env` that's never committed.

## Dependencies

- `bash` (any modern version)
- `curl` (pre-installed on macOS)
- `jq` (optional — prettifies JSON output). Install with `brew install jq`.

## Safety

- `.env` is gitignored at the repo root
- Scripts validate all required env vars before making any API call — no silent misconfig
- No scenario edits exposed via these scripts. Only `run`, `status`, and `incomplete` — all read or trigger operations
