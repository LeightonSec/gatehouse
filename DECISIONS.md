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
**LOCKED** · 2026-11-02 · amended 2026-11-03 (version pin and key-auth proof added from Phase 0)
- Local (key) auth disabled on the Foundry resource. Only the gateway's managed identity holds a data-plane role.
- **Target model:** `gpt-5.4-mini` on the **DataZoneStandard** (EU data zone) deployment type. Generally available, retires 2027-09-21, and offered on the EU data zone in Sweden Central and all three DR candidates.
- **Rejected:** `gpt-5.1` on Standard (Sweden-only processing). Full-size model, and no DR candidate offers it at the same level, so failover would silently widen where prompts are processed. `gpt-5-nano` retires 2027-02-09, too soon. GlobalStandard as the target: processing anywhere in the world contradicts the project's governance story.
- **Model and deployment type are Terraform variables**, never hard-coded.
- **Model version pinned, automatic upgrades off** (`version_upgrade_option = "NoAutoUpgrade"`). An auto-upgrade mid-project would make Phase 3 detection measurements incomparable. At retirement the deployment stops rather than silently changing; the retirement date is tracked above.
- **Key auth off is a tested control, not a setting.** Proven in the Phase 0 sandbox (see `docs/phase-0-sandbox.md`): with `disableLocalAuth` on, keys cannot be listed, a key captured beforehand is refused (403), and an Entra token still works (200). Phase 2 repeats this as an automated gate check.

### Deliberate deviation: development quota
The free trial subscription has zero quota for every EU data zone and Standard option (checked 2026-11-02 with `az cognitiveservices usage list`). The only small model with quota is `gpt-5-mini` on GlobalStandard.
- Phases 2 and 3 run on `gpt-5-mini` GlobalStandard. Acceptable because all traffic is synthetic (D10).
- When the trial is upgraded to pay-as-you-go, request DataZoneStandard quota for `gpt-5.4-mini` and switch the two variables.
- **Must be switched before the Phase 6 write-up.** The README states which deployment type the published results used.
- **Fallback if EU data zone quota is refused:** stay on GlobalStandard and record it in the README as a known limitation of a personal subscription, not a design choice.

## D5. Regions
**LOCKED** (primary) · 2026-11-02 / **PROPOSED** (DR)
- **Primary:** Sweden Central.
- **DR:** France Central, provisional. Re-check at the start of Phase 5.
- Checked 2026-11-02. France Central offers the target model on the EU data zone, API Management Basic v2 and Standard v2, and Prompt Shields both as a separate Content Safety resource and as a Foundry guardrail.
- **Rejected DR candidates:** Germany West Central (Prompt Shields only as a Foundry guardrail, not as a separate Content Safety resource; see D9). Norway East and Switzerland North (outside the EU data zone, so failover would move processing out of the EU). Poland Central passes every check and is the fallback.
- Sources: `az cognitiveservices model list`, the API Management SKU list via `az rest`, and Microsoft Learn's Content Safety region availability page (dated 2026-09-18).

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
- **OPEN sub-question for Phase 3:** run Prompt Shields as a separate Content Safety resource called from gateway policy, or as a Foundry guardrail on the model deployment. It affects which regions qualify (see D5). Known limits either way: 10,000-character prompts, trained mainly on English.
- **Phase 0 data point:** the default Foundry guardrail (`Microsoft.DefaultV2`) blocked a textbook jailbreak at user input. Its own panel lists **no controls** for indirect prompt injection, sensitive data leakage or task drift. So the guardrail is configured explicitly in Terraform; "the default guardrail is on" is not claimed as a control. Guardrail results are returned in every response (`prompt_filter_results`), which Phase 4 can log and detect on.
- **Response-side screening:** currently deferred (D12). The guardrail gaps above strengthen the case for pulling it into Phase 3. Decide at D9 sign-off.

## D10. Logging and data
**PROPOSED**
- All traffic is synthetic, so full prompts are logged for detection work. A production deployment would redact or hash prompt bodies, and the README will say so.
- Gateway and screening logs go to one Log Analytics workspace with Sentinel, analytics tier only, with a daily ingestion cap.
- **The subscription-wide Activity log is ingested, not just the project's resource groups.** Phase 0 showed a role grant made at subscription scope does not appear in a resource-group-filtered log.
- Detections on sensitive control-plane operations (for example List Keys, role assignments) filter by caller. Phase 0 showed the portal calls List Keys dozens of times in the background, so an unfiltered rule would be noise.
- Blocked prompts and verdicts go to immutable, geo-redundant Blob storage (the evidence ledger).

## D11. Cost controls
**PROPOSED**
- Environment exists only while building or demoing. `destroy` is tested from Phase 1.
- Budget alerts at 50 / 80 / 100%.
- Baseline from the saved calculator estimate: SEK 274/month (gateway at 40 hours + Sentinel at 0.1 GB/day); about SEK 107/month during the Sentinel trial.
- **Model token costs must account for reasoning tokens.** In Phase 0, a five-word answer from `gpt-5-mini` used 336 completion tokens, 320 of them reasoning tokens. Per-app quotas and cost estimates are sized on measured usage, not visible output.
- Azure quota for these models is expressed in thousands of tokens per minute (500 = 500K TPM), confirmed in the deployment screen.
- **Subscription safety net, outside Terraform by design:** a subscription-wide budget (`subscription-safety-net`, alerts at 50/80/100% actual and 100% forecast) and the free trial spending limit. Not part of the Gatehouse stack. Budget amount to be corrected once the billing currency is confirmed.

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
