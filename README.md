# Make + Claude + Salesforce — Lead Triage Pipeline

A working reference implementation of the pattern: **new Lead in Salesforce → Claude generates a structured triage summary → write back to the Lead**, with explicit error handling and audit trail.

Built as a proof-of-concept for a recruiting-workflow discussion, but the pattern is general — any Salesforce object where a field needs an LLM-generated value on record create.

## What's in here

| Path | What it is |
|---|---|
| `force-app/main/default/` | Salesforce metadata — custom fields, custom object, layouts, tab, permission set |
| `docs/change_log/` | Production-style change log entry, with full prompt text preserved inline |
| `make/claude_body.json` | The Claude API request body used by the Make scenario (ready to paste into the HTTP module) |
| `blueprints/` | Make.com scenario blueprint export *(exported after the scenario was built, credentials redacted)* |

## Architecture

```
┌─────────────────┐      ┌──────────────┐      ┌─────────────────┐      ┌──────────────┐
│ Salesforce      │      │  Make.com    │      │  Anthropic API  │      │ Salesforce   │
│ Watch Records   │ ───▶ │  If-else     │ ───▶ │  POST /messages │ ───▶ │ Update Lead  │
│ (Lead created)  │      │  guard       │      │  claude-haiku   │      │ (summary +   │
└─────────────────┘      └──────────────┘      └─────────────────┘      │  timestamp + │
                                │                       │               │  version)    │
                         ┌──────┴──────┐         ┌──────┴──────┐        └──────────────┘
                         │ Else branch │         │ Error branch│
                         │ (silent end)│         │ → SF log    │
                         └─────────────┘         │   record    │
                                                 └─────────────┘
```

### Design choices

- **Guard before spend.** The If-else filter blocks Claude calls on Leads missing required inputs. No tokens burned on incomplete data.
- **`tool_use` for output consistency.** Claude is forced to call a `save_candidate_summary` tool with a fixed `{"summary": "..."}` schema. No free-form text, no "Here's the summary:" preambles, no parsing surprises.
- **Two-layer length protection.** `max_tokens` caps physical response size; a Make-side guard trims at the nearest sentence boundary before writing to the CRM. If the output is empty or under 20 chars (signal of malformed response), it routes to the error branch rather than writing garbage.
- **Errors never corrupt the target field.** Transient failures (429, 5xx) use Make's native retry. Hard failures (4xx, auth) route to a dedicated error branch that logs to `AI_Integration_Log__c` — the Lead's summary field stays untouched.
- **Prompt version stamped on every write.** `AI_Prompt_Version__c` captures which prompt generated each summary. Combined with the full prompt text preserved in the change log, this gives a two-sided audit trail.

## Deploy to your own dev org

### Prerequisites

- Salesforce CLI: `sf --version` (install via `npm install -g @salesforce/cli` if missing)
- A Salesforce Developer Edition org (sign up free at `developer.salesforce.com/signup`)
- A Make.com account (free tier is fine for demo)
- An Anthropic API key

### Salesforce deploy

```bash
# 1. Authorize your dev org (opens browser; credentials never touch the CLI)
sf org login web --alias claude-demo --instance-url https://login.salesforce.com

# 2. Deploy the metadata
sf project deploy start --target-org claude-demo

# 3. Assign yourself the permission set
sf org assign permset --name AI_Integration_Demo --target-org claude-demo

# 4. Open the org to verify
sf org open --target-org claude-demo
```

Verification: Setup → Object Manager → Lead → Fields & Relationships should show the custom fields. App Launcher should list "AI Integration Logs".

### Make.com scenario

The manual build takes ~15 minutes. Modules:

1. **Salesforce → Watch Records** (Lead, order by CreatedDate, limit 10)
2. **If-else router** — 1st branch condition: `Job_Title__c` Exists AND `Region__c` Exists AND `AI_Candidate_Summary__c` Does not exist
3. **Anthropic Claude → Make an API Call** — `POST /v1/messages`, body from `make/claude_body.json`
4. **Salesforce → Update a Record** — write `AI_Candidate_Summary__c`, `AI_Last_Updated__c`, `AI_Prompt_Version__c`
5. **Salesforce → Create a Record** on error handler of module 3 — write to `AI_Integration_Log__c`

See `docs/change_log/` for the complete prompt text and parameter details.

## Smoke test

Seed a Lead with all required fields, then trigger the Make scenario:

```bash
sf data create record --sobject Lead --target-org claude-demo \
  --values "FirstName=Klaus LastName=Becker Company='Black Forest Machinery GmbH' \
    Title='DevOps Engineer' Country=Germany \
    Job_Title__c='Senior DevOps Engineer' Region__c=Schwarzwald \
    Years_Experience__c=7 Availability_Weeks__c=4 German_Level__c=Native \
    Skills__c='Kubernetes, Terraform, AWS, GitLab CI, Python, Ansible, Docker'"
```

Run Once in Make, then:

```bash
sf data query --target-org claude-demo \
  --query "SELECT LastName, AI_Prompt_Version__c, AI_Candidate_Summary__c \
           FROM Lead WHERE LastName='Becker'"
```

Expected: `AI_Candidate_Summary__c` populated with a 2-3 sentence triage summary, `AI_Prompt_Version__c = v2026-04-19-a-triage`.

## Rollback

Non-destructive (seconds): disable the Make scenario via the scenario-editor toggle. Existing SF data is untouched.

Full reverse (destructive): generate a destructive changeset for the custom fields + object, deploy via `sf project deploy start --manifest ...`. Not included in this repo — demo org cleanup is faster in the UI.

## Change log discipline

`docs/change_log/` contains a full entry for the initial deployment. The structure includes:

- What changed, why, components touched, credential location
- **Full prompt text preserved inline** — not a link — for future diffing
- Model + parameters with rationale
- Test evidence: sandbox run count, sample input/output, error cases validated + not yet validated
- Rollback plan, runbook, cost ceiling + budget alert

Every prompt or schema change gets a new entry. Prompt version in SF + full text in change log creates a two-sided audit trail — any record tells you its generation context, any change log entry tells you which records are affected.

## Cost envelope

At Claude Haiku 4.5 current pricing, the per-call cost is roughly **$0.0003** for this prompt shape (~480 input tokens, ~140 output tokens).

Monthly projections:

| Applicant volume / month | Estimated cost |
|---|---|
| 500 | ~$0.15 |
| 2,500 | ~$0.75 |
| 10,000 | ~$3 |
| 50,000 | ~$15 |

A budget alert at 2× expected volume lives in the Anthropic console as an early-warning tripwire.

## License

MIT. Fork freely.

## Contact

Built by [Nigam Goyal](https://github.com/nigamgoyal).
