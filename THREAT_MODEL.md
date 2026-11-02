# Gatehouse: Threat Model

**Status:** DRAFT, awaiting sign-off · Method: STRIDE per data flow · Scope: decisions D1 to D12

## System and data flows

| ID | Flow | Trust boundary crossed |
| --- | --- | --- |
| DF1 | Simulated app → gateway (prompt + Entra token) | Untrusted caller → Azure |
| DF2 | Gateway → Content Safety Prompt Shields | Within Azure |
| DF3 | Gateway → judge on Container Apps | Within Azure, into an LLM-backed component |
| DF4 | Gateway → model deployment (Foundry) | Within Azure |
| DF5 | Gateway, screening and model logs → Log Analytics / Sentinel | Within Azure |
| DF6 | Blocked prompts and verdicts → evidence ledger (Blob) | Within Azure |
| DF7 | GitHub Actions → Azure control plane (deploy) | GitHub → Azure |
| DF8 | Terraform → remote state storage | GitHub / local → Azure |

## Threats

Each mitigation has a test. A threat is only "mitigated" once its test has passed with evidence in the repo.

| ID | Flow | STRIDE | Threat | Mitigation | Test (phase) |
| --- | --- | --- | --- | --- | --- |
| T1 | DF1 | Spoofing | Caller uses a stolen or wrong-audience token, or impersonates another app | Validate issuer, audience and app ID allowlist at the gateway (D8); short-lived tokens | Wrong-audience and non-allowlisted tokens are rejected (P2) |
| T2 | DF1 | Tampering | Direct prompt injection or jailbreak in user input | Two screening layers in series (D9) | Replay honeypot corpus, record detection and false-positive rates per layer (P3) |
| T3 | DF1 | DoS | One app floods tokens and burns budget or starves others | Per-app `llm-token-limit` on the app ID claim; budget alerts (D11) | Over-quota app is throttled; documented near-concurrency overshoot measured (P2) |
| T4 | DF4 | Elevation | Caller bypasses the gateway and calls the model directly | Key auth disabled; only the gateway's managed identity has a data-plane role (D4); Policy denies re-enabling keys | Direct call rejected; Sentinel rule fires on any non-gateway caller (P2, P4) |
| T5 | DF3 | Tampering / Elevation | Injection aimed at the judge itself: the attacker's prompt manipulates the LLM-backed screen into passing it | Prompt passed as delimited data; structured output only; no tools; unparseable output = block (D9) | Corpus includes judge-targeted payloads; any pass is a finding (P3) |
| T6 | DF2, DF3 | DoS / fail-open | A screening layer times out or errors and the request goes through unscreened | Gateway policy fails closed on error, timeout or bad response (D9) | Stop the judge and break Content Safety access: requests are blocked, not passed (P3) |
| T7 | DF4 | Info disclosure | Model output leaks system prompt or sensitive content | **Accepted risk:** response-side screening deferred (D12). Synthetic data only, so no real data to leak | Recorded deferral; revisit in Phase 6 |
| T8 | DF5 | Repudiation | Attacker or careless admin deletes or disables logging to hide activity | Policy protects diagnostic settings; Activity log alert on changes; ledger is write-once (D10) | Disabling a diagnostic setting is blocked or alerted (P4, P5) |
| T9 | DF5 | Info disclosure | Logged prompts expose sensitive content to anyone with workspace read | Synthetic data only; workspace RBAC limited; production redaction noted (D10) | RBAC review in gate checklist (P4) |
| T10 | DF6 | Tampering | Evidence ledger altered after the fact | Immutability policy on the container; geo-redundant storage | Overwrite/delete attempt fails (P5) |
| T11 | DF7 | Spoofing / Elevation | A malicious PR or fork obtains Azure credentials through the pipeline | OIDC subject pinned to a protected environment with required reviewer; fork PRs get no credentials (D7) | Fork PR run has no Azure token; unapproved run cannot reach `apply` (P1) |
| T12 | DF7 | Tampering | Supply-chain compromise via an action, provider or module | Actions pinned to SHAs; provider lock file; security-gate + IaC scanner fail closed (D7) | Scanner and pin checks are required status checks (P1) |
| T13 | DF7 | Elevation | Deploy identity is over-privileged and becomes a takeover path | Scoped to project resource groups; constrained RBAC Administrator, no Owner (D7) | Deploy identity cannot assign Owner or act outside its scope (P1) |
| T14 | DF8 | Info disclosure / Tampering | Terraform state leaked or altered | Private storage, RBAC-only access, versioning; no secrets in state by design (D6) | Anonymous access fails; state contains no credentials (P1) |
| T15 | Repo | Info disclosure | Public repo exposes environment identifiers or secrets | No secrets by design; IDs held in GitHub variables and uncommitted tfvars; secret scanning on (D2) | Secret scan clean on every push (P1) |

## Accepted risks and deferrals
- **T7:** response-side screening deferred to Phase 6 or beyond.
- **Network exposure:** the gateway and model use public endpoints locked down by identity, not private networking. Private endpoints are a Phase 6 stretch (D12).
- **Quota overshoot:** `llm-token-limit` can be briefly exceeded by near-concurrent requests (documented behaviour). Measured and recorded, not prevented.

## Sign-off
- [ ] Reviewed by Leighton
