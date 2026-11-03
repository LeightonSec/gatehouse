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
**LOCKED** · 2026-11-02 · amended 2026-11-03 (version pin and key-auth proof from Phase 0; separate judge model resource)
- Local (key) auth disabled on every Foundry resource. On each model resource, exactly one managed identity holds a data-plane role (see "Two model resources" below).
- **Target model:** `gpt-5.4-mini` on the **DataZoneStandard** (EU data zone) deployment type. Generally available, retires 2027-09-21, and offered on the EU data zone in Sweden Central and all three DR candidates.
- **Rejected:** `gpt-5.1` on Standard (Sweden-only processing). Full-size model, and no DR candidate offers it at the same level, so failover would silently widen where prompts are processed. `gpt-5-nano` retires 2027-02-09, too soon. GlobalStandard as the target: processing anywhere in the world contradicts the project's governance story.
- **Model and deployment type are Terraform variables**, never hard-coded.
- **Model version pinned, automatic upgrades off** (`version_upgrade_option = "NoAutoUpgrade"`). An auto-upgrade mid-project would make Phase 3 detection measurements incomparable. At retirement the deployment stops rather than silently changing; the retirement date is tracked above.
- **Key auth off is a tested control, not a setting.** Proven in the Phase 0 sandbox (see `docs/phase-0-sandbox.md`): with `disableLocalAuth` on, keys cannot be listed, a key captured beforehand is refused (403), and an Entra token still works (200). Phase 2 repeats this as an automated gate check.
- **Two model resources, exactly one data-plane identity each.** The app model resource is callable only by the gateway's managed identity. A separate judge model resource (same region, deployment type and pinning rules) is callable only by the judge's managed identity. A manipulated judge therefore cannot reach the app model.
  - Rejected: routing the judge through the gateway (needs a route that skips screening, and couples the two so one failing breaks both).
  - Rejected: a second deployment on the same resource (role assignments are believed to apply to the whole resource rather than one deployment; unverified, and this design avoids depending on it).
  - Model quota is shared across both resources in the region.

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
**LOCKED** · 2026-11-03
- azurerm for core resources; azapi where Foundry features are not yet in azurerm (Microsoft's own guidance).
- Remote state in a dedicated storage account, bootstrapped separately from the main stack, with versioning on and public access off.
- Provider lock file committed. Modules: `identity`, `gateway`, `model`, `screening`, `observability`, `governance`.
- **Bootstrap:** a separate, minimal `bootstrap/` Terraform root creates what CI cannot create for itself: the state storage account, the deploy identity and its GitHub federated credential, the project resource groups, the deploy identity's role assignments, and the Entra app registrations for the simulated apps (D8).
  - The **only** Terraform ever applied from a local machine, and only by Leighton (CLAUDE.md rule 6 exception).
  - Kept as small as possible: it is the most privileged code in the repo.
  - Its state is local and gitignored. It holds no secrets by design.
  - The DR drill reruns it in the DR region before the main stack, so the bootstrap is tested too.
  - Rejected: an `az` script (hard to review, no record of intended state, drifts) and the portal (not repeatable).

## D7. CI/CD: GitHub Actions with OIDC, no stored secrets
**LOCKED** · 2026-11-03 · deploy identity type **OPEN** until verified (see below)
- Deploy identity: a **user-assigned managed identity** with a federated credential, so no client secret ever exists. **To verify:** GitHub OIDC support for user-assigned managed identities, against Microsoft's docs. Fallback: an app registration with a federated credential (still no secret).
- Federated credentials pinned to a GitHub **environment** subject (for example `repo:LeightonSec/gatehouse:environment:azure`), not to the whole repo.
- `fmt` / `validate` run on every PR with no cloud credentials. `plan` and `apply` run only in the protected environment, with Leighton as required reviewer.
- PRs from forks never receive cloud credentials. This matters because the repo is public.
- All actions pinned to commit SHAs. security-gate and an IaC scanner (Checkov or tfsec) are required checks that fail closed.
- **The deploy identity holds no Microsoft Graph permissions.** It cannot create or change Entra app registrations or users; those are created in the bootstrap (D6).
- Deploy identity scoped to the project resource groups. Role assignments use RBAC Administrator with a condition limiting which roles it can grant, not Owner.

## D8. App authentication at the gateway: Entra tokens, no subscription keys
**LOCKED** · 2026-11-03
- Each simulated app gets its own Entra app registration, **created in the bootstrap (D6), not by CI**. Adding an app later means a reviewed bootstrap run.
- Gateway validates issuer, audience and an allowlist of app IDs, then keys token quotas on the app ID claim.
- API Management subscription keys are not used, so there is no shared secret to leak.

## D9. Screening: two layers in series, fail closed
**LOCKED** · 2026-11-03 · guardrail versus separate resource **OPEN** for Phase 3 (see below)
1. Content Safety Prompt Shields, called from gateway policy.
2. Leighton's judge (ai-firewall / llm-honeypot semantic layer) on Container Apps, with its own managed identity and its own model resource (D4).
- If either layer errors, times out or returns something unparseable, the request is **blocked**, not passed. This applies the fail-open audit rule from security-gate.
- The judge treats prompts as untrusted data: delimited input, structured output only, no tool access. This also closes the standing TODO on LLM-layer input isolation for ai-firewall.
- **OPEN sub-question for Phase 3:** run Prompt Shields as a separate Content Safety resource called from gateway policy, or as a Foundry guardrail on the model deployment. It affects which regions qualify (see D5). Known limits either way: 10,000-character prompts, trained mainly on English.
- **Phase 0 data point:** the default Foundry guardrail (`Microsoft.DefaultV2`) blocked a textbook jailbreak at user input. Its own panel lists **no controls** for indirect prompt injection, sensitive data leakage or task drift. So the guardrail is configured explicitly in Terraform; "the default guardrail is on" is not claimed as a control. Guardrail results are returned in every response (`prompt_filter_results`), which Phase 4 can log and detect on.
- **Response-side screening: in scope for Phase 3** (moved from D12, 2026-11-03, on the Phase 0 guardrail findings). The judge also screens model **output** before it reaches the app, for system-prompt leakage and sensitive content.
  - Same fail-closed rule: if response screening errors or times out, the response is withheld, not passed.
  - A **canary string** is planted in each app's system prompt; any response containing it is blocked and logged as a leak.
  - Streaming responses must be buffered for screening, so streaming is off (or screened as a whole before release) for apps behind the gateway.
  - Cost: roughly doubles judge calls. Measured in Phase 3, not estimated.

## D10. Logging and data
**LOCKED** · 2026-11-03
- All traffic is synthetic, so full prompts are logged for detection work. A production deployment would redact or hash prompt bodies, and the README will say so.
- Gateway and screening logs go to one Log Analytics workspace with Sentinel, analytics tier only, with a daily ingestion cap.
- **The subscription-wide Activity log is ingested, not just the project's resource groups.** Phase 0 showed a role grant made at subscription scope does not appear in a resource-group-filtered log.
- Detections on sensitive control-plane operations (for example List Keys, role assignments) filter by caller. Phase 0 showed the portal calls List Keys dozens of times in the background, so an unfiltered rule would be noise.
- Blocked prompts and verdicts go to immutable, geo-redundant Blob storage (the evidence ledger).

## D11. Cost controls
**LOCKED** · 2026-11-03 · budget amount **OPEN** until billing currency confirmed
- Environment exists only while building or demoing. `destroy` is tested from Phase 1.
- Budget alerts at 50 / 80 / 100%.
- Baseline from the saved calculator estimate: SEK 274/month (gateway at 40 hours + Sentinel at 0.1 GB/day); about SEK 107/month during the Sentinel trial.
- **Model token costs must account for reasoning tokens.** In Phase 0, a five-word answer from `gpt-5-mini` used 336 completion tokens, 320 of them reasoning tokens. Per-app quotas and cost estimates are sized on measured usage, not visible output.
- Azure quota for these models is expressed in thousands of tokens per minute (500 = 500K TPM), confirmed in the deployment screen.
- **Subscription safety net, outside Terraform by design:** a subscription-wide budget (`subscription-safety-net`, alerts at 50/80/100% actual and 100% forecast) and the free trial spending limit. Not part of the Gatehouse stack. Budget amount to be corrected once the billing currency is confirmed.

## D12. Explicitly deferred or out of scope
**LOCKED** · 2026-11-03
- Private networking (VNet integration, private endpoints): deferred to the Phase 6 stretch, because it needs Standard v2.
- ~~Response-side screening~~: no longer deferred; moved into Phase 3 (see D9).
- Multi-region active-active: out of scope. DR is a rebuild drill, not hot standby.
- Intune, M365 and Conditional Access for users: out of scope.

## D13. Evaluation data: how screening is measured
**LOCKED** · 2026-11-03

The Phase 3 detection and false-positive rates are the project's headline evidence, so the data behind them is handled as carefully as the infrastructure.

- **Two sets:** an **attack set** (to measure detection) and a **benign set** (to measure false positives). Both include all three apps' traffic shapes: HR policy questions, support ticket text, code requests.
- **Benign set built as hand-written seeds, expanded with an LLM, then reviewed by Leighton line by line.** Pure LLM generation tends to produce prompts that are too clean, so false-positive rates come out flattering.
  - The expansion model comes from a **different model family** from the judge's model, so the judge isn't scored on a writing style it finds unusually familiar.
- **Hard negatives are deliberate.** The benign set includes legitimate prompts that look suspicious: security questions, a support ticket quoting a phishing email, "ignore the previous ticket, this one supersedes it". These are where false positives actually happen.
- **Split before tuning:** each set is divided into a **tuning split** (used to adjust thresholds and prompts) and a **held-out evaluation split**, frozen and hash-recorded **before** any tuning. Published rates come only from the held-out split. Tuning on the evaluation data would make the results meaningless.
  - **Split by family, not at random.** Each attack family (and each source or seed) sits entirely in one split. Near-identical variants on both sides would make the evaluation split effectively "seen" and inflate detection.
- **Size from statistics, not taste.** Sizes refer to the **held-out evaluation split**, not the total.
  - Target: **at least 300 benign prompts in the held-out split** (so about 600 benign in total with a 50/50 split). With zero false positives, 300 supports a 95% upper bound of about 1%; 150 would only support about 2%.
  - The attack held-out split is also large enough to report a detection rate with a confidence interval, per family where possible.
- **How results are reported:** every published rate is given as a **one-sided 95% confidence bound with the method named** (exact Clopper-Pearson; the "rule of three", 3/*n*, is its zero-failure shorthand). Rates are reported **per layer** (Prompt Shields, guardrail, judge) **and for the whole pipeline**, for both prompts and responses. "Under 1%" is never quoted as a target. For example, one false positive in 300 moves the bound to about 1.6%, and the README says so.
- **Provenance and licensing checked before commit.** Every dataset in the public repo records where it came from and its licence. Anything that can't be published stays out of the repo.
  - Prompts captured by llm-honeypot from real attackers are reviewed for personal data **and scanned with gitleaks** before inclusion. Attackers sometimes paste real-looking keys and credentials; GitHub push protection is the backstop, not the first check.

## D14. Licence: MIT
**LOCKED** · 2026-11-03
- Matches the rest of the LeightonSec portfolio. Apache-2.0's patent grant was the alternative; marginal for this project.
- Copyright holder: Leighton Wilson (personal name; can be changed later in a single commit).
- **Third-party code keeps its own licence.** Anything taken from elsewhere (Microsoft modules or samples, code from other repos) keeps its original copyright notice and licence, recorded in `THIRD_PARTY_NOTICES.md`. MIT and Apache-2.0 both require that notice to travel with the code.
- **Datasets keep their own licences** (D13). Each records its source, licence and, if LLM-generated or expanded, the model that generated it (the provider's terms govern use of that output). The MIT licence does not override a dataset's original terms.
  - **Non-commercial (NC) datasets are not committed**; the repo links to them instead.
  - **Share-alike (SA) datasets may be committed**, in their own folder with their licence alongside. Share-alike binds only those data files, not the code. A deliberate choice to keep useful public attack corpora available.
- **Vulnerability reports** go through GitHub's private vulnerability reporting, as described in `SECURITY.md`. No email address is published.

---

## Phase 1 gate: pass criteria
- [ ] All PROPOSED decisions above signed off or amended. (Remaining: D5 DR region.)
- [x] Threat model reviewed and signed off (2026-11-03).
- [ ] Full `apply` and `destroy` round trip from CI, with zero secrets stored in GitHub or the repo.
- [ ] Gate security checklist: critical-property check, data provenance, scanner coverage, dependency surface, deferrals recorded.
