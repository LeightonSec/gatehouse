# Gatehouse: Threat Model

**Status:** Signed off by Leighton, 2026-11-03 · Method: STRIDE per data flow · Scope: decisions D1 to D14

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
| DF9 | Judge → judge model resource | Within Azure, from an LLM-backed component that handles attacker-controlled input |

## Threats

Each mitigation has a test. A threat is only "mitigated" once its test has passed with evidence in the repo.

| ID | Flow | STRIDE | Threat | Mitigation | Test (phase) |
| --- | --- | --- | --- | --- | --- |
| T1 | DF1 | Spoofing | Caller uses a stolen or wrong-audience token, or impersonates another app | Validate issuer, audience, client ID allowlist and the `invoke` roles claim at the gateway (D8); short-lived tokens | Wrong-audience, non-allowlisted and role-less tokens are rejected (P2) |
| T2 | DF1 | Tampering | Direct prompt injection or jailbreak in user input | Two screening layers in series (D9) | Replay honeypot corpus, record detection and false-positive rates per layer (P3) |
| T3 | DF1 | DoS | One app floods tokens and burns budget or starves others | Per-app `llm-token-limit` keyed on the calling identity's client ID claim; budget alerts (D11) | Over-quota app is throttled; documented near-concurrency overshoot measured (P2) |
| T4 | DF4 | Elevation | Caller bypasses the gateway and calls the model directly, including via data-plane roles granted silently by portal workflows (Phase 0 found a subscription-wide "Foundry User" grant) | Key auth disabled; each model resource has exactly one data-plane identity: the gateway for the app model, the judge for the judge model, both system-assigned so no federated credential can ever be added to them (D4); every role assignment owned by Terraform; Policy denies re-enabling keys | Captured key refused (403) and Entra works (200); gate check lists all data-plane roles on each model resource **including inherited ones** and fails unless each has exactly one principal (gateway for the app model, judge for the judge model); Sentinel rule fires on any caller other than the expected identity for each model resource (P2, P4) |
| T5 | DF3, DF9 | Tampering / Elevation | Injection aimed at the judge itself: the attacker's prompt manipulates the LLM-backed screen into passing it, or into misusing its own model access | Prompt passed as delimited data; structured output only; no tools; unparseable output = block (D9); judge runs on its own identity and model resource, so a manipulated judge cannot reach the app model (D4) | Corpus includes judge-targeted payloads; any pass is a finding (P3) |
| T6 | DF2, DF3 | DoS / fail-open | A screening layer times out or errors and the request goes through unscreened | Gateway policy fails closed on error, timeout or bad response (D9) | Stop the judge and break Content Safety access: requests are blocked, not passed (P3) |
| T7 | DF4 | Info disclosure | Model output leaks system prompt or sensitive content | Judge screens responses before release, fail closed; canary string in each system prompt, any response containing it blocked and logged (D9). The default guardrail lists no control for this (Phase 0) | Extraction attempts in the corpus; zero canary strings in released responses; response-screen detection and false-positive rates recorded (P3) |
| T8 | DF5 | Repudiation | Attacker or careless admin deletes or disables logging to hide activity | Policy protects diagnostic settings; Activity log alert on changes; ledger is write-once (D10) | Disabling a diagnostic setting is blocked or alerted (P4, P5) |
| T9 | DF5 | Info disclosure | Logged prompts expose sensitive content to anyone with workspace read | Synthetic data only; workspace RBAC limited; production redaction noted (D10) | RBAC review in gate checklist (P4) |
| T10 | DF6 | Tampering | Evidence ledger altered after the fact | Immutability policy on the container; geo-redundant storage | Overwrite/delete attempt fails (P5) |
| T11 | DF7 | Spoofing / Elevation | A malicious PR or fork obtains Azure credentials through the pipeline | OIDC subject pinned to a protected environment with required reviewer; fork PRs get no credentials (D7) | Fork PR run has no Azure token; unapproved run cannot reach `apply`; bootstrap read-back confirms the credential subject matches what it built from tfvars, and the script's check confirms it matches GitHub's reported subject exactly (P1) |
| T12 | DF7 | Tampering | Supply-chain compromise via an action, provider or module | Actions pinned to SHAs; provider lock file; security-gate + IaC scanner fail closed (D7) | Scanner and pin checks are required status checks (P1) |
| T13 | DF7 | Elevation | Deploy identity is over-privileged and becomes a takeover path | No control rights over `rg-gatehouse-bootstrap`, where it and the app identities live; constrained RBAC Administrator on `rg-gatehouse` only, no Owner; Managed Identity Operator only on each app identity; no Microsoft Graph permissions and no subscription-level roles (D7) | Deploy identity cannot assign Owner, act outside `rg-gatehouse`, call Graph to create an app registration, add a federated credential to itself or an app identity, or attach itself to a resource (P1) |
| T14 | DF8 | Info disclosure / Tampering | Terraform state leaked or altered | Private storage, RBAC-only access, versioning; no secrets in state by design (D6) | Anonymous access fails; state contains no credentials (P1) |
| T15 | Repo | Info disclosure | Public repo exposes environment identifiers or secrets | No secrets by design; IDs held as GitHub environment secrets (masked in public Actions logs) and uncommitted tfvars; secret scanning on (D2) | Secret scan clean on every push (P1) |
| T16 | DF1, DF4 | Tampering | Indirect prompt injection: instructions hidden in content an app passes to the model (a support ticket, a policy document). The default guardrail lists no control for this (Phase 0) | Judge screens all prompt content as untrusted data (D9); guardrail configured explicitly rather than left on defaults | Corpus includes payloads embedded in ticket and document text; detection rate recorded per layer (P3) |
| T17 | Bootstrap | Elevation | The bootstrap is applied locally with Leighton's Owner rights, and `scripts/configure-github.sh` runs with his `gh` token, which reaches every LeightonSec repo. A compromised machine or session at that moment, or a malicious change slipped into either, gains control of the deploy identity, its trust with GitHub, or other repos | Bootstrap and script kept minimal and reviewed line by line before each run; script names the repo on every `gh` call and fails closed; applied rarely and only by Leighton, under MFA; same pre-commit scanners; Claude Code never applies it (D6) | Bootstrap and script diffs reviewed and signed off before each run; post-apply read-back of every role assignment created; script's subject check passes (P1) |

## Residual risk
Screening (T2, T5, T7, T16) is probabilistic. Prompt Shields, the guardrail and the judge will each miss some attacks, and an LLM-backed judge can itself be manipulated. These threats are **mitigated with measured residual risk**, never fully prevented. The Phase 3 detection and false-positive rates are that measurement.

## Accepted risks and deferrals
- **Network exposure:** the gateway and model use public endpoints locked down by identity, not private networking. Private endpoints are a Phase 6 stretch (D12).
- **Quota overshoot:** `llm-token-limit` can be briefly exceeded by near-concurrent requests (documented behaviour). Measured and recorded, not prevented.
- **Global processing during development (D4):** until EU data zone quota is granted, the model runs on GlobalStandard, so prompts may be processed outside the EU. Accepted because all traffic is synthetic (D10). Switched before the Phase 6 write-up, or recorded in the README as a known limitation if quota is refused.

## Sign-off
- [x] Reviewed and signed off by Leighton, 2026-11-03
