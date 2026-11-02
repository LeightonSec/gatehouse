# Gatehouse: Decisions Log

Status key: **LOCKED** (signed off) · **PROPOSED** (awaiting Leighton's sign-off) · **OPEN** (needs research or a call)

No code is written against a PROPOSED or OPEN decision.

---

## D1. Project name: Gatehouse
**LOCKED** · 2026-11-02
Renamed from working title "Sentinel Gate" to avoid confusion with Microsoft Sentinel, which the project also uses.

## D2. Repository: public under LeightonSec from day one
**LOCKED** · 2026-11-02
Commit history is part of the portfolio value, and a public repo forces the no-secrets design from the first commit.
- Before the first push: confirm git identity, remote and GitHub account (standing rule).
- Tenant ID, subscription ID and object IDs are not secrets, but they are kept out of the repo anyway: GitHub environment variables and an uncommitted `terraform.tfvars`.

## D3. Gateway: standalone API Management Basic v2, defined in Terraform
**LOCKED** · 2026-11-02
- Cost: SEK 2.68/hour (Azure calculator, Nov 2026), about SEK 107/month at 40 hours.
- **Rejected alternative:** Foundry portal "AI Gateway". It is the same Basic v2 instance underneath, possibly free for the first 100,000 calls (sources conflict on whether the base charge still applies). It is created through the portal with no Terraform resource found for the association, which breaks the one-command destroy path and the DR rebuild drill.
- Optional later: a one-hour experiment in a scratch resource group to measure the Foundry route's real billing, written up as supporting evidence.

## D4. Model host: Foundry resource + project + model deployment, Entra-only
**PROPOSED**
- Local (key) auth disabled on the Foundry resource. Only the gateway's managed identity holds a data-plane role.
- Model: the smallest current chat model available in the chosen regions. **OPEN** until availability is checked (see D5).

## D5. Regions
**PROPOSED** (primary) / **OPEN** (DR)
- Primary: Sweden Central.
- DR region: to be chosen once model availability is confirmed. Must have the same model, API Management v2 and Content Safety Prompt Shields.

## D6. Infrastructure as code: Terraform with azurerm + azapi
**PROPOSED**
- azurerm for core resources; azapi where Foundry features are not yet in azurerm (Microsoft's own guidance).
- Remote state in a dedicated storage account, bootstrapped separately from the main stack, with versioning on and public access off.
- Provider lock file committed. Modules: `identity`, `gateway`, `model`, `screening`, `observability`, `governance`.

## D7. CI/CD: GitHub Actions with OIDC, no stored secrets
**PROPOSED**
- Federated credentials pinned to a GitHub **environment** subject (for example `repo:LeightonSec/gatehouse:environment:azure`), not to the whole repo.
- `fmt` / `validate` run on every PR with no cloud credentials. `plan` and `apply` run only in the protected environment, with Leighton as required reviewer.
- PRs from forks never receive cloud credentials. This matters because the repo is public.
- All actions pinned to commit SHAs. security-gate and an IaC scanner (Checkov or tfsec) are required checks that fail closed.
- Deploy identity scoped to the project resource groups. Role assignments use RBAC Administrator with a condition limiting which roles it can grant, not Owner.

## D8. App authentication at the gateway: Entra tokens, no subscription keys
**PROPOSED**
- Each simulated app gets its own Entra app registration.
- Gateway validates issuer, audience and an allowlist of app IDs, then keys token quotas on the app ID claim.
- API Management subscription keys are not used, so there is no shared secret to leak.

## D9. Screening: two layers in series, fail closed
**PROPOSED**
1. Content Safety Prompt Shields, called from gateway policy.
2. Leighton's judge (ai-firewall / llm-honeypot semantic layer) on Container Apps.
- If either layer errors, times out or returns something unparseable, the request is **blocked**, not passed. This applies the fail-open audit rule from security-gate.
- The judge treats prompts as untrusted data: delimited input, structured output only, no tool access. This also closes the standing TODO on LLM-layer input isolation for ai-firewall.

## D10. Logging and data
**PROPOSED**
- All traffic is synthetic, so full prompts are logged for detection work. A production deployment would redact or hash prompt bodies, and the README will say so.
- Gateway and screening logs go to one Log Analytics workspace with Sentinel, analytics tier only, with a daily ingestion cap.
- Blocked prompts and verdicts go to immutable, geo-redundant Blob storage (the evidence ledger).

## D11. Cost controls
**PROPOSED**
- Environment exists only while building or demoing. `destroy` is tested from Phase 1.
- Budget alerts at 50 / 80 / 100%.
- Baseline from the saved calculator estimate: SEK 274/month (gateway at 40 hours + Sentinel at 0.1 GB/day); about SEK 107/month during the Sentinel trial.

## D12. Explicitly deferred or out of scope
**PROPOSED**
- Private networking (VNet integration, private endpoints): deferred to the Phase 6 stretch, because it needs Standard v2.
- Response-side screening (checking model output for leakage): deferred. Prompt Shields scans input only. Logged as an accepted risk in the threat model.
- Multi-region active-active: out of scope. DR is a rebuild drill, not hot standby.
- Intune, M365 and Conditional Access for users: out of scope.

---

## Phase 1 gate: pass criteria
- [ ] All PROPOSED decisions above signed off or amended.
- [ ] Threat model reviewed and signed off.
- [ ] Full `apply` and `destroy` round trip from CI, with zero secrets stored in GitHub or the repo.
- [ ] Gate security checklist: critical-property check, data provenance, scanner coverage, dependency surface, deferrals recorded.
