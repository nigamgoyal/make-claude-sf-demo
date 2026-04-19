# Make.com Blueprints

## `lead_triage_v1.json`

Exports the full "Lead Triage" Make.com scenario — the same one the Salesforce metadata in this repo is designed to pair with.

### Before import

The blueprint uses placeholder values for sensitive fields:
- `"__IMTCONN__": 0` — connection IDs for Salesforce and Anthropic are set to `0`. Make will prompt you to link your own connections on import.
- `"<SF_CONNECTION>"` / `"<ANTHROPIC_CONNECTION>"` — connection labels replaced with placeholders.

No API keys are present in this file.

### Import

1. Make.com → **Scenarios** → `+ Create a new scenario` → click the `⋯` menu (top toolbar) → `Import Blueprint`
2. Select `lead_triage_v1.json`
3. On import, Make will prompt you to either select existing connections or create new ones for:
   - Salesforce (OAuth to your claude-demo dev org)
   - Anthropic Claude (paste your API key)
4. Once connections are linked, the scenario's Salesforce field references resolve against the current org schema. If you haven't deployed the SFDX metadata in this repo yet, do that first (`sf project deploy start --target-org claude-demo`).

### What the scenario does

- Watches `Lead` on create in Salesforce (limit 10 per run, ordered by CreatedDate)
- Routes through an If-else guard: only calls Claude when `Job_Title__c` and `Region__c` are both populated and `AI_Candidate_Summary__c` is empty
- Calls Anthropic Messages API with `tool_use` forcing a `save_candidate_summary` response schema
- Updates the Lead with summary, timestamp, and prompt version on success
- On any Claude API error, writes a row to `AI_Integration_Log__c` with request ID, error body, and Lead reference — without touching the Lead's summary field

See the main repo `README.md` for architecture and the `docs/change_log/` entry for prompt details + parameters.
