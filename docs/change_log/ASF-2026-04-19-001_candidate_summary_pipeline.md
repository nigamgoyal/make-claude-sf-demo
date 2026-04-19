# Change Log: AI-SF Integration — Candidate Summary Pipeline

**Change ID:** ASF-2026-04-19-001
**Date:** 2026-04-19
**Author:** Nigam Goyal
**Reviewer:** _pending — assign before prod rollout_
**Deployed to:** Salesforce Developer Edition sandbox (`claude-demo` org, org id redacted)
**Production rollout:** _gated on reviewer sign-off + UAT with a sample of real portal applicants_

---

## 1. What changed

Added a Make.com scenario ("Lead Triage v1") that, on Lead creation, generates a 2–3 sentence triage summary via the Claude API and writes it back to a custom `AI_Candidate_Summary__c` field on the Lead, along with a timestamp and prompt-version tag.

## 2. Why

Recruiter triage of incoming applications through the regional job portals is a manual bottleneck. The goal is to cut the per-Lead first-pass review from roughly 60–90 seconds to under 10 seconds by surfacing fit and red flags in a consistent format the account manager can scan before deciding to prioritize, queue, or decline.

## 3. Components touched

### Salesforce custom fields added on the Lead object
| API name | Type | Purpose |
|---|---|---|
| `AI_Candidate_Summary__c` | Long Text Area (2000, 5 visible lines) | Claude-generated triage summary |
| `AI_Last_Updated__c` | Date/Time | Timestamp of last successful write |
| `AI_Prompt_Version__c` | Text (40) | Version tag of prompt used, for audit/diff |
| `AI_Status__c` | Picklist (restricted): `Generated`, `Failed`, `Skipped` | End-user-visible state of the last AI run on this Lead |
| `Job_Title__c` | Text (255) | Role the candidate applied for |
| `Region__c` | Picklist (restricted) | Source portal: Oberland, Bodensee, Schwarzwald, Allgaeu, Baden, Ulm |
| `Years_Experience__c` | Number (4,1) | Total relevant years, self-reported |
| `Skills__c` | Long Text Area (1000) | Skills / technologies / certifications |
| `Availability_Weeks__c` | Number (3,0) | Weeks until start (proxies notice period) |
| `German_Level__c` | Picklist (restricted) | Native, C2, C1, B2, B1, A2, None |

### Salesforce retry affordance
**`Retry AI Summary`** quick action on the Lead page layout, wired to a screen flow (`AI_Summary_Retry`) that clears the four `AI_*` fields. Because the Make scenario watches Leads by Updated Time, clearing the fields re-triggers processing on the next poll. End users don't touch Make; a recruiter who sees `AI_Status__c = Failed` clicks the button and the summary regenerates.

### Salesforce permission set
**`AI_Integration_Demo`** — grants field-level access to the new Lead custom fields including `AI_Status__c`.

### Make.com scenario
**"Integration Salesforce"** (scenario id `4795249`, US2 region). Modules:
1. Salesforce → Watch Records (Lead, **by Updated Time**, limit 10) — retry-friendly
2. If-else router with "Required inputs present" branch. Else branch → Salesforce Update Lead, sets `AI_Status__c = Skipped`
3. Anthropic Claude → Make an API Call (`POST /v1/messages`)
4. Salesforce → Update a Record on success — writes summary + timestamp + prompt version, sets `AI_Status__c = Generated`
5. On Claude error handler → Salesforce Update Lead, sets `AI_Status__c = Failed` → `Break` directive, which pushes the bundle onto Make's Incomplete Executions queue for operator review / retry

Error context (status code + body) is preserved in Make's Incomplete Executions queue for 48h; no separate Salesforce log object is maintained. `AI_Status__c` on the Lead is the user-visible signal, and Make's execution history is the audit trail.

### Credential location
- **Anthropic API key:** Make connection `My Anthropic Claude connection`. Not stored in Salesforce.
- **Salesforce OAuth:** Make connection `My Salesforce connection`. Requires `refresh_token` / `offline_access` scope for token refresh.

---

## 4. Prompt (version `v2026-04-19-a-triage`)

Preserved in full for diffing when prompt is iterated.

### System prompt

```
You help Recruiting Now account managers triage new job applicants from regional job portals in southern Germany. Generate a short internal triage summary (2-3 sentences, max 1900 chars, professional English, third person, no markdown, no bullets, no first-person) that lets a recruiter decide in 5 seconds whether to prioritize, queue, or decline. Weigh in this order: (1) fit between current background and applied role, (2) regional fit via source portal, (3) practical constraints (German language is important for Mittelstand SMEs; B2 or below is a constraint; plus notice period), (4) red flags or data gaps. Say 'not specified' when data is missing. Neutral, factual, no sales language, do not sugar-coat mismatches. Call the save_candidate_summary tool only. No other output.
```

### User prompt template

```
Generate a triage summary. Name: {{FirstName}} {{LastName}}. Current role: {{Title}} at {{Company}}. Experience: {{Years_Experience__c}} years. Skills: {{Skills__c}}. Availability: {{Availability_Weeks__c}} weeks. German level: {{German_Level__c}}. Applied for: {{Job_Title__c}} via {{Region__c}} portal.
```

### Tool schema (forces structured output)

```json
{
  "name": "save_candidate_summary",
  "description": "Save a triage summary to the CRM.",
  "input_schema": {
    "type": "object",
    "properties": {
      "summary": {
        "type": "string",
        "description": "2-3 sentence triage summary, max 1900 chars, third person, no markdown."
      }
    },
    "required": ["summary"]
  }
}
```

`tool_choice` is fixed to `{"type": "tool", "name": "save_candidate_summary"}` so Claude is forced to call the tool rather than returning free text. This is the primary consistency lever.

---

## 5. Model and parameters

| Parameter | Value | Rationale |
|---|---|---|
| Model | `claude-haiku-4-5` | Short structured summaries don't need Sonnet/Opus. Meaningfully cheaper at production volume. Revisit if QA flags drift. |
| Temperature | `0.3` | Consistency across similar inputs, not variety |
| `max_tokens` | `1024` | Caps physical response size; ~4096 chars upper bound. Field limit is 2000 chars so there's further headroom. |
| Response format | `tool_use` with `save_candidate_summary` | Structured output; kills preambles |
| API endpoint | `POST https://api.anthropic.com/v1/messages` | |
| `anthropic-version` header | `2023-06-01` | |

---

## 6. Test evidence

### Sandbox runs
- **3 test Leads seeded** for end-to-end validation:
  - Mueller (Oberland, Quality Manager) — complete data, expected happy-path
  - Schmidt (Ulm, Head of Data Science, B2 German, Berlin-based) — complete data but multiple soft-conflict signals
  - Weber (Allgaeu, no Job_Title) — incomplete data, expected filter skip
- **1 live-trigger Lead** (Klaus Becker) — fresh create after scenario save; processed end-to-end.

### Sample input → output (Klaus Becker, Lead id `00QdM00000btrsoUAA`)

**Input:**
```
Name: Klaus Becker
Current role: DevOps Engineer at Black Forest Machinery GmbH
Experience: 7 years
Skills: Kubernetes, Terraform, AWS, GitLab CI, Python, Ansible, Docker
Availability: 4 weeks
German level: Native
Applied for: Senior DevOps Engineer via Schwarzwald portal
```

**Output (written to `AI_Candidate_Summary__c`):**
```
Klaus Becker is a native German speaker with 7 years of DevOps engineering experience at a regional Mittelstand machinery company, demonstrating strong technical alignment with the Senior DevOps Engineer role through proficiency in Kubernetes, Terraform, AWS, and CI/CD tools. Regional fit is excellent via the Schwarzwald portal, and availability at 4 weeks' notice is acceptable. No red flags identified; candidate presents as a qualified internal-market progression opportunity.
```

Stamped `AI_Prompt_Version__c = v2026-04-19-a-triage`, `AI_Last_Updated__c = 2026-04-19T14:56:43Z`.

### Error cases validated
- **Guard / missing input:** Lead with blank `Job_Title__c` → If-else routes to Else branch → no API call, `AI_Status__c = Skipped` written to the Lead. Confirmed with Weber.
- **Invalid API key (401):** Pointed Claude module at `/v1/messages-broken` on a re-run → routed to error branch → `AI_Status__c = Failed` written to Lead, `AI_Candidate_Summary__c` untouched, bundle pushed to Incomplete Executions queue. Recruiter clicks **Retry AI Summary** → fields cleared → scenario reprocesses on next poll.
- **Malformed response body (400):** Encountered during initial dev when pretty-printed JSON contained literal newlines; fixed by compacting to single-line JSON and validating with `python -c "json.loads(...)"` before committing to Make.

### Not yet validated (carry to UAT)
- 429 rate-limit retry behavior under real load
- Response length edge case — output exactly at the field-length boundary
- Concurrent writes to the same Lead (e.g., webhook fires twice on a rapid update)

---

## 7. Rollback plan

**To disable (non-destructive, seconds):**
1. In Make: turn off the `Integration Salesforce` scenario (toggle at top-left of scenario).
2. Existing SF Lead data is untouched. `AI_Candidate_Summary__c` values remain on records already processed.

**To fully reverse (destructive, ~10 min):**
1. Turn off the scenario as above.
2. Disconnect the Anthropic connection in Make (safeguard against accidental re-enable).
3. Via SFDX: `sf project deploy start --manifest manifest/destructive/package.xml --post-destructive-changes manifest/destructive/destructiveChanges.xml`. A destructive manifest listing the Lead custom fields + `AI_Summary_Retry` flow + quick action can be generated on request; the current repo ships with the cleanup manifest for the `AI_Integration_Log__c` object as a reference.
4. Make Incomplete Executions for this scenario can be cleared from the Make UI or left to expire at 48h.

---

## 8. Runbook — if something fails

| Symptom | First check | Second check | Owner |
|---|---|---|---|
| No new summaries on recently created Leads | Make execution history — is the scenario running? Any recent errors? | `SELECT COUNT(Id) FROM Lead WHERE CreatedDate = TODAY AND AI_Last_Updated__c = null` | TBD |
| Summaries populated but look wrong | `AI_Prompt_Version__c` on the affected records — matches current deployed prompt? | Re-run one record manually via Make "Run once" with verbose log | TBD |
| Sudden spike in error rate | `SELECT COUNT(Id) FROM Lead WHERE AI_Status__c = 'Failed' AND LastModifiedDate >= LAST_N_DAYS:1` + cross-reference Make Incomplete Executions | Anthropic console → API key status, rate limit headroom | TBD |
| Sudden spike in cost | Anthropic console → daily usage graph | Model hasn't silently changed; `max_tokens` hasn't been inflated | TBD |
| Field-length truncation complaints | The guard layer is in place? (trim-at-sentence logic) | Prompt's "max 1900 chars" instruction still in system prompt | TBD |

Owner column to be filled in before prod rollout.

---

## 9. Cost ceiling

### Per-call estimate
- Input: ~480 tokens (system prompt ~280 + user prompt ~150 + tool schema ~50)
- Output: ~140 tokens (typical 2–3 sentence summary)
- Claude Haiku 4.5 at current pricing: roughly **$0.0003 per call** (rounded up from the per-token rate; exact figure varies with Anthropic pricing)

### Monthly projections (adjust when real application volume is known)
| Applicant volume / month | Estimated cost |
|---|---|
| 500 | ~$0.15 |
| 2,500 | ~$0.75 |
| 10,000 | ~$3 |
| 50,000 | ~$15 |

### Budget alert
Configure in Anthropic console at **2× expected monthly volume** — early warning for a runaway loop, prompt bloat, or bad retry behavior. Default proposed: **$30/month** alert for volume up to ~10K Leads/month.

### Kill-switch
If monthly run-rate exceeds the ceiling, disable the Make scenario (section 7) before re-enabling after root-cause analysis.

---

## 10. Open items / followups

- [ ] Assign reviewer
- [ ] Run 100-Lead UAT on a sample of real historical applicants (sanitized) before prod enable
- [ ] Validate 429 retry behavior under simulated rate-limit pressure
- [ ] Define owner for each runbook row
- [ ] Decide whether summaries get a second layer (e.g., auto-flag "likely decline" based on specific red-flag phrases) — holding pending audience clarification from Peter Posztos (internal triage vs employer brief)
- [ ] Blueprint export committed to `blueprints/lead_triage_v1.json` with credentials redacted
- [ ] Destructive metadata manifest for full rollback (not required for dev org)

---

_End of change log entry. Next iteration (prompt tone change or input-field expansion) will be logged as `ASF-2026-04-19-002` or the next sequential ID._
