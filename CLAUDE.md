# Gatehouse: instructions for Claude Code

## What this is
A governed AI gateway on Azure: apps call a model only through API Management, which authenticates them with Entra, enforces per-app token quotas, screens both prompts and responses (Prompt Shields or a Foundry guardrail, then Leighton's judge from ai-firewall / llm-honeypot, which runs on its own separate model), and logs everything to Microsoft Sentinel. Public portfolio repo under LeightonSec.

## Source of truth
- `DECISIONS.md`: every architectural decision and its status.
- `THREAT_MODEL.md`: threats, mitigations and the test that proves each one.
If code and these files disagree, the files win. Raise the conflict; don't resolve it silently.

Local background notes may exist outside version control. They predate the decisions log and are partly out of date. Where they disagree with `DECISIONS.md`, the decisions log wins. Never copy content from untracked or ignored files into tracked files.

## Roles
- Architecture and strategy: Claude (chat), with Leighton.
- Implementation: you (Claude Code).
- Review and sign-off: Leighton. Nothing is "done" until he signs it off.

## Hard rules
1. **No code against a PROPOSED or OPEN decision.** Only LOCKED decisions can be implemented. If a task needs an unlocked decision, stop and ask.
2. **Git identity check every session.** Before any commit or push, show the git user, the remote URL and the GitHub account in use, and wait for Leighton to confirm.
3. **No secrets, anywhere.** No keys, connection strings, tokens, tenant or subscription IDs in the repo. Identity-based auth only. If something seems to need a secret, stop and ask.
4. **Fail closed.** Any screening, validation or check that errors, times out or can't parse must block, never pass. Silent fail-open is a defect.
5. **Pin everything.** GitHub Actions pinned to commit SHAs; Terraform provider lock file committed.
6. **No `terraform apply` or `destroy` from a local machine.** Read-only `az` and `terraform plan` are fine. **Sole exception:** the `bootstrap/` root (D6), which only Leighton applies, by hand. You never apply or destroy it, even if asked mid-task: stop and hand him the command. The same applies to `scripts/configure-github.sh` and any change to GitHub repository settings: only Leighton runs them.
7. **Not sure? Ask.** Don't guess at Azure behaviour; check the docs or run a read-only command, and say which you did.
8. **No plan files in the repo.** `terraform plan` output contains subscription and tenant IDs. Show Leighton summaries only, and never save a plan file inside the repo.
9. **The repo is the master copy.** Changes to committed files arrive as exact old-text/new-text edits, applied with your edit tool, which refuses any edit whose old text doesn't match exactly once. If a whole replacement file must come in, diff it against the committed version and show Leighton every difference before copying it.

## Current phase
Phase 1: Foundations. Gate criteria are at the bottom of `DECISIONS.md`.

## Current task: draft the bootstrap for review (no apply)
Prerequisite: Leighton installs Terraform himself, after his soak-time check. Until `terraform version` works, stop and tell him.

Draft, for Leighton's line-by-line review (T17):
1. `bootstrap/`: a Terraform root implementing D6, D7 and D8 using only azurerm and azuread, with providers pinned to releases at least 7 days old and `.terraform.lock.hcl` committed. It creates the state storage account, the resource groups, the deploy user-assigned managed identity and its federated credential (subject built from tfvars per D7), the deploy identity's role assignments, and the three app registrations. It **outputs** the client, tenant and subscription IDs. Include a `terraform.tfvars.example` with placeholders only.
2. `scripts/configure-github.sh`, exactly as D7 describes.
3. A short note listing every resource and role assignment the bootstrap creates, so Leighton can check the read-back against it.

Propose the file layout first and wait for Leighton's OK before writing code. Run `terraform fmt` and `terraform validate`; run `plan` only if Leighton asks, and share a summary only. Never apply or destroy, and never run the script.
