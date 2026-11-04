# Gatehouse: Decisions Log

Status key: **LOCKED** (signed off) · **PROPOSED** (awaiting Leighton's sign-off) · **OPEN** (needs research or a call)

No code is written against a PROPOSED or OPEN decision.

---

## D1. Project name: Gatehouse
**LOCKED** · 2026-11-02
Renamed from working title "Sentinel Gate" to avoid confusion with Microsoft Sentinel, which the project also uses.

## D2. Repository: public under LeightonSec from day one
**LOCKED** · 2026-11-02 · amended 2026-11-03 (IDs held as GitHub secrets, not variables)
Commit history is part of the portfolio value, and a public repo forces the no-secrets design from the first commit.
- Before the first push: confirm git identity, remote and GitHub account (standing rule).
- Tenant ID, subscription ID and object IDs are not secrets, but they are kept out of the repo anyway: GitHub environment **secrets** (so public Actions logs mask them; see D7) and an uncommitted `terraform.tfvars`.

## D3. Gateway: standalone API Management Basic v2, defined in Terraform
**LOCKED** · 2026-11-02
- Cost: SEK 2.68/hour (Azure calculator, Nov 2026), about SEK 107/month at 40 hours.
- **Rejected alternative:** Foundry portal "AI Gateway". It is the same Basic v2 instance underneath, possibly free for the first 100,000 calls (sources conflict on whether the base charge still applies). It is created through the portal with no Terraform resource found for the association, which breaks the one-command destroy path and the DR rebuild drill.
- Optional later: a one-hour experiment in a scratch resource group to measure the Foundry route's real billing, written up as supporting evidence.

## D4. Model host: Foundry resource + project + model deployment, Entra-only
**LOCKED** · 2026-11-02 · amended 2026-11-03 (version pin and key-auth proof from Phase 0; separate judge model resource; system-assigned gateway and judge identities) · amended 2026-11-04 (data-plane role named)
- Local (key) auth disabled on every Foundry resource. On each model resource, exactly one managed identity holds a data-plane role (see "Two model resources" below).
- **Target model:** `gpt-5.4-mini` on the **DataZoneStandard** (EU data zone) deployment type. Generally available, retires 2027-09-21, and offered on the EU data zone in Sweden Central and all three DR candidates.
- **Rejected:** `gpt-5.1` on Standard (Sweden-only processing). Full-size model, and no DR candidate offers it at the same level, so failover would silently widen where prompts are processed. `gpt-5-nano` retires 2027-02-09, too soon. GlobalStandard as the target: processing anywhere in the world contradicts the project's governance story.
- **Model and deployment type are Terraform variables**, never hard-coded.
- **Model version pinned, automatic upgrades off** (`version_upgrade_option = "NoAutoUpgrade"`). An auto-upgrade mid-project would make Phase 3 detection measurements incomparable. At retirement the deployment stops rather than silently changing; the retirement date is tracked above.
- **Key auth off is a tested control, not a setting.** Proven in the Phase 0 sandbox (see `docs/phase-0-sandbox.md`): with `disableLocalAuth` on, keys cannot be listed, a key captured beforehand is refused (403), and an Entra token still works (200). Phase 2 repeats this as an automated gate check.
- **Two model resources, exactly one data-plane identity each.** The app model resource is callable only by the gateway's managed identity. A separate judge model resource (same region, deployment type and pinning rules) is callable only by the judge's managed identity. A manipulated judge therefore cannot reach the app model.
  - **The gateway and judge use system-assigned managed identities.** Microsoft's docs state that federated credentials can't be configured on system-assigned identities, so nothing outside Azure can ever act as them, even if the pipeline is compromised. Their model access is an ordinary Azure role granted by CI (D7).
  - **The data-plane role is Cognitive Services OpenAI User**, for both the gateway and the judge. Microsoft's API Management documentation names it for a managed identity calling a Foundry resource, and of the built-in roles that can call chat completions it is the narrowest on the OpenAI path: no key listing, no deployment changes (all built-in roles checked 2026-11-04). It still permits other inference operations such as embeddings, images, assistants and realtime; the gateway exposes only chat completions. A custom role holding only the chat completions data action is a Phase 2 hardening option. If Phase 2 routes the gateway through the Foundry project endpoint instead, this choice is reopened.
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
**LOCKED** · 2026-11-03 · amended 2026-11-04 (local module sources only)
- azurerm for core resources; azapi where Foundry features are not yet in azurerm (Microsoft's own guidance); **azuread for Entra objects** (the gateway's app registration and its role grants), used only in the bootstrap.
- Terraform and every provider are pinned to releases at least 7 days old, per the standing soak-time rule.
- **Local module sources only.** Every module is a local folder: no registry, Git, S3, GCS or archive sources. Terraform downloads remote modules with go-getter, and Terraform 1.17.1 (pinned), 1.17.0, 1.16.7 and the development branch (checked 2026-11-04) are all built with go-getter 1.8.6, which is affected by HCSEC-2026-39 and HCSEC-2026-44. With local modules, neither flaw is reachable through module downloads. CI fails if any module `source` doesn't start with `./` or `../`. Revisited once a Terraform release built with go-getter 1.8.10 or later passes the soak.
- **Plan files are never saved to the repo.** A plan contains subscription and tenant IDs; only summaries are shared.
- Remote state in a dedicated storage account, bootstrapped separately from the main stack, with versioning on and public access off.
- Provider lock file committed. Modules: `identity`, `gateway`, `model`, `screening`, `observability`, `governance`.
- **Bootstrap:** a separate, minimal `bootstrap/` Terraform root creates what CI cannot create for itself: the state storage account, the deploy identity and its GitHub federated credential, two resource groups (below), the deploy identity's role assignments, the gateway's Entra app registration, and the three app identities with their gateway role (D8).
  - **Two resource groups.** `rg-gatehouse-bootstrap` holds the state storage account, the deploy identity and the app identities; the deploy identity has no control rights there except Managed Identity Operator on each app identity (D7), plus data access to the state container. `rg-gatehouse` is where CI deploys. If the deploy identity controlled its own resource group, it could add a federated credential to itself trusting any branch (bypassing the reviewer rule) or weaken the state storage.
  - **Read-back:** `scripts/verify-bootstrap.sh`, run by Leighton after each apply, uses read-only `az` commands to compare the federated credential's subject with the expected value and to list every role assignment the deploy identity holds, exiting non-zero on any mismatch. (azurerm and azuread can't re-read a federated credential.)
  - **State backup:** an encrypted copy of the bootstrap state is kept outside the Mac after each apply. It holds IDs, not secrets.
  - The **only** Terraform ever applied from a local machine, and only by Leighton (CLAUDE.md rule 6 exception).
  - Kept as small as possible: it is the most privileged code in the repo.
  - Its state is local and gitignored. It holds no secrets by design.
  - The DR drill reruns it in the DR region before the main stack, so the bootstrap is tested too.
  - Rejected: an `az` script (hard to review, no record of intended state, drifts) and the portal (not repeatable).

## D7. CI/CD: GitHub Actions with OIDC, no stored secrets
**LOCKED** · 2026-11-03 · amended 2026-11-03 (managed identity confirmed; GitHub immutable subject format; scoped rights) · placement of subscription-wide governance **OPEN** for Phase 4
- Deploy identity: a **user-assigned managed identity** with a federated credential, so no client secret ever exists. Confirmed supported for GitHub Actions in Microsoft's docs ("Create trust between a user-assigned managed identity and an external identity provider", checked 2026-11-03).
- Federated credential pinned to a GitHub **environment** subject, not to the whole repo.
  - **This repo uses GitHub's immutable subject format** (repos created after 15 July 2026). GitHub's API reports `use_immutable_subject: true`, so the subject has the form `repo:<owner>@<owner_id>/<repo>@<repo_id>:environment:azure`. The prefix comes from GitHub's API; the `:environment:azure` ending follows GitHub's documented pattern and is proven by the first CI login.
  - The subject is **built explicitly in the bootstrap** from the IDs in its uncommitted tfvars, never typed by hand or generated by the portal's "GitHub Actions" form.
  - **A wrong subject fails silently:** Azure accepts the credential and the login later fails with no clear error. So it is checked twice, each by the part that can see the relevant side:
    - **Bootstrap (Azure-only):** after applying, reads the credential back and confirms its subject matches the one it built from tfvars. Catches typos and drift.
    - **Script (GitHub access):** compares that subject with GitHub's reported `sub_claim_prefix` plus `:environment:azure`, exiting non-zero on any difference. Only the script can do this, as the only part with GitHub access.
  - Limits recorded from Microsoft's docs: at most 20 federated credentials per identity; no wildcards; exactly one audience, `api://AzureADTokenExchange`; credentials created one at a time (parallel creation fails); token requests retried shortly after creation (propagation delay).
- **GitHub side: no GitHub token ever touches Terraform.** Split three ways:
  - The bootstrap stays Azure-only and **outputs** the three IDs (client, tenant, subscription).
  - `scripts/configure-github.sh`, reviewed like all code, stores them as GitHub **environment secrets**, not variables. On a public repo the Actions logs are public, and only secrets are masked. It then runs the GitHub-side subject check described above. Written for bash, `set -euo pipefail`, with `--repo LeightonSec/gatehouse` on every `gh` call so it can never act on another repo.
  - The `azure` environment is created **once** by Leighton with `gh`: required reviewer Leighton; deployment branch rule **`main` only**; "prevent self-review" **off** (he is the sole reviewer). It persists through Azure rebuilds; a DR drill only re-runs the script for the new IDs.
  - The script is run only by Leighton, interactively, from his own `gh` session, and stores nothing.
  - Rejected: the github Terraform provider in the bootstrap. It needs a GitHub token inside Terraform, Leighton's `gh` token reaches every LeightonSec repo, and it adds another dependency.
- `fmt` / `validate` run on every PR with no cloud credentials. `plan` and `apply` run only in the protected environment, with Leighton as required reviewer.
- PRs from forks never receive cloud credentials. This matters because the repo is public.
- All actions pinned to commit SHAs. security-gate and an IaC scanner (Checkov or tfsec) are required checks that fail closed.
- **The deploy identity holds no Microsoft Graph permissions.** It cannot create or change Entra app registrations or users; those are created in the bootstrap (D6).
- **Deploy identity's rights:** Contributor and a constrained RBAC Administrator on `rg-gatehouse` only, never Owner; data access to the state container only. The RBAC Administrator condition limits grantable roles to the model data-plane role (D4); more are added only when a later phase proves a need.
- **Managed Identity Operator is granted separately on each app identity, never on `rg-gatehouse-bootstrap`.** Granted on the group, it would also cover the deploy identity itself, letting a compromised run attach the deploy identity to a container it controls and keep its rights outside the reviewer gate.
- **No subscription-level roles.** Separation of duties: the deploy identity never manages the guardrails that constrain it (policy, the subscription Activity log export). Where those subscription-wide pieces live, in the bootstrap or a separate layer Leighton applies, is **OPEN** and decided before Phase 4.

## D8. App authentication at the gateway: Entra tokens, no subscription keys
**LOCKED** · 2026-11-03 · amended 2026-11-03 (managed identities for the apps; one gateway app registration)
- **Each simulated app runs as its own Container Apps job with its own user-assigned managed identity.** Managed identities get tokens with no secret, certificate or app registration (rule 3).
- **One Entra app registration represents the gateway API:** the audience the apps request tokens for. It defines an `invoke` app role, with assignment required, granted to the three app identities.
- The app identities, the gateway registration and the role grants are **created in the bootstrap (D6), not by CI.** Granting an app role is an Entra (Graph) operation, and the deploy identity has no Graph permissions (D7). Adding an app later means a reviewed bootstrap run.
- The app identities live in `rg-gatehouse-bootstrap`, so the deploy identity **cannot add a federated credential to one**, which would let something outside Azure act as that app and outlive the pipeline run. The deploy identity does still choose what code runs as each app when it deploys them; the `azure` environment's reviewer rule is the control for that.
- **The gateway checks the token itself:** issuer, audience, an allowlist of the three app identities, **and that the `roles` claim contains `invoke`**. Whether Entra also refuses to issue app-only tokens to unassigned identities is **unverified**; Phase 2 tests it with an unassigned identity. The gateway check holds either way.
- Token quotas are keyed on the calling identity's client ID claim.
- API Management subscription keys are not used, so there is no shared secret to leak.

## D9. Screening: two layers in series, fail closed
**LOCKED** · 2026-11-03 · guardrail versus separate resource **OPEN** for Phase 3 (see below)
1. Content Safety Prompt Shields, called from gateway policy.
2. Leighton's judge (ai-firewall / llm-honeypot semantic layer) on Container Apps, with its own managed identity and its own model resource (D4).
- If either layer errors, times out or returns something unparseable, the request is **blocked**, not passed. This applies the fail-open audit rule from security-gate.
- The judge treats prompts as untrusted data: delimited input, structured output only, no tool access. This also closes the standing TODO on LLM-layer input isolation for ai-firewall.
- **OPEN sub-question for Phase 3:** run Prompt Shields as a separate Content Safety resource called from gateway policy, or as a Foundry guardrail on the model deployment. One factor: abuse monitoring scores traffic to the models, while the Code of Conduct says "Transmitting harmful content to Content Safety through the intended use of the service will not by itself be considered a violation". Screening as a separate resource *before* the model therefore keeps most attack traffic out of what gets scored (T18). It affects which regions qualify (see D5). Known limits either way: 10,000-character prompts, trained mainly on English.
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

## D15. Regulatory alignment: built in, not retrofitted
**LOCKED** · 2026-11-04

Gatehouse is not claimed to be in scope of any of these laws. It is designed so that an organisation that *is* in scope could use the same design to meet its obligations, and the evidence is kept as the build goes. Not legal advice. Sources were checked on 2026-11-04 and are listed in the map, primary sources first.

- **`docs/compliance-map.md` grows with the build.** Every phase gate updates it: each control, where it is implemented, the test that proves it (THREAT_MODEL.md), and the obligation it supports. Covered:
  - **NIS2**, implemented in Sweden by the Cybersecurity Act (SFS 2025:1506, in force 15 January 2026): the security measures, and the incident clock in chapter 2: notification within 24 hours of becoming aware of a significant incident (section 5), within 72 hours (section 6), and a final report within one month (section 8).
  - **CRA** (Regulation (EU) 2024/2847): reporting obligations (Article 14) apply from 11 September 2026; fully applicable from 11 December 2027 (European Commission).
  - **AI Act**: Gatehouse is a governance control for AI deployers, not a high-risk system. The Digital Omnibus on AI (Regulation (EU) 2026/1744) entered into force on 27 July 2026 (EUR-Lex). Its new high-risk dates (2 December 2027 for Annex III, 2 August 2028 for Annex I) come from two independent secondary sources and are **not yet verified against the regulation's text**.
  - **GDPR**: cross-referenced to D10 (synthetic data, production redaction) and D13 (personal-data review of captured attacker prompts).
- **Built CRA-ready by default.**
  - As a public portfolio repo, Gatehouse is likely outside the CRA: free and open-source software "not monetised by their manufacturers" is not a commercial activity (recital 18), and hosting on an open repository alone is not making a product available (recital 20).
  - **The line to watch:** charging for technical support beyond cost recovery can be a commercial activity (recital 15). **Deploying or supporting Gatehouse for paying clients would likely make Leighton a manufacturer**, so a CRA assessment comes before any paid use.
  - It is built as if in scope anyway, so that line can be crossed without a retrofit: **an SBOM (CycloneDX) is generated in CI** on every build of `main` and attached to releases (D7 pipeline); vulnerability disclosure via `SECURITY.md` (in place); pinned dependencies (rule 5); a short support and update statement in the README.
- **NIS2 detection-to-notification timing is measured.** Phase 4 detections record when an incident becomes known, and the Phase 5 drill shows whether the 24-hour notification could be met from that moment.

## D16. Testing conduct on Microsoft services
**LOCKED** · 2026-11-04

Phase 3 deliberately sends attacks at the project's own deployments. Microsoft permits and recommends this within limits, and the limits shape the tests. Sources: the Microsoft Enterprise AI Services Code of Conduct (version 4.0, 1 May 2026; it replaced the separate Azure OpenAI code), the Penetration Testing Rules of Engagement summary, and the red-teaming guidance (all checked 2026-11-04).

- **Allowed:** the Code of Conduct permits otherwise-prohibited content "solely (1) to evaluate, train, fine-tune, and improve safety systems and applications for the customer's use". The Rules of Engagement explicitly encourage activities including "attempting to break out of AI system boundaries", and Microsoft recommends red teaming your own LLM applications. No advance notice is needed to test resources you own.
- **High-Risk Content is out of scope.** Microsoft defines two High-Risk categories: "Malicious cyber activity" and CBRN weapons. Safeguards for both are mandatory for all customers, and intentionally generating or attempting to generate either needs prior approval "through the applicable Limited Access Service program", a formal application. For a security project the cyber category is the one to watch: **any attack prompt asking the model to write malware, exploit code or similar is High-Risk.** So:
  - The attack set (D13) contains **no payloads aimed at producing either High-Risk category**, and captured honeypot prompts are filtered for them before replay.
  - Injection success is measured with **harmless objectives**: leaking the canary string (D9), revealing the system prompt, or emitting a marker word. This measures whether the screens hold without generating anything harmful.
- **No denial-of-service testing.** The Rules of Engagement prohibit "Denial of Service (DoS) testing of any kind" and automated testing that "generates excessive traffic". Quota tests (T3) use the minimum traffic needed to cross a deliberately small quota; corpus replays are modest and batched.
- **An authorisation note is kept ready:** what is tested, against which resources, and why. If Azure's abuse detection flags the testing (T18), Microsoft's guidance is to respond with the authorisation and a description of the in-scope activity.

---

## Phase 1 gate: pass criteria
- [ ] All PROPOSED decisions above signed off or amended. (Remaining: D5 DR region.)
- [x] Threat model reviewed and signed off (2026-11-03).
- [ ] Full `apply` and `destroy` round trip from CI, with zero secrets stored in GitHub or the repo.
- [ ] Gate security checklist: critical-property check, data provenance, scanner coverage, dependency surface, deferrals recorded.
- [ ] `docs/compliance-map.md` updated for this phase's controls (D15). Every later phase gate carries the same item.
