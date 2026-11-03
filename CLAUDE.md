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
6. **No `terraform apply` or `destroy` from a local machine.** Read-only `az` and `terraform plan` are fine. **Sole exception:** the `bootstrap/` root (D6), which only Leighton applies, by hand. You never apply or destroy it, even if asked mid-task: stop and hand him the command.
7. **Not sure? Ask.** Don't guess at Azure behaviour; check the docs or run a read-only command, and say which you did.

## Current phase
Phase 1: Foundations. Gate criteria are at the bottom of `DECISIONS.md`.

## Current task (read-only, no code)
Verify the open item in D7: does GitHub Actions OIDC work with a federated credential on a **user-assigned managed identity** (not an app registration)? Check Microsoft's and GitHub's official docs, quote the relevant lines with links, and note any limits (for example, subject formats or a maximum number of federated credentials). Also check: can a **Free Trial** subscription request additional Azure OpenAI / Foundry model quota (specifically DataZoneStandard for `gpt-5.4-mini` in Sweden Central), or does it have to be upgraded to pay-as-you-go first? If the docs don't say clearly, report that rather than guess. Do not edit `DECISIONS.md`: Leighton locks decisions.
