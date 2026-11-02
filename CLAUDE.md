# Gatehouse: instructions for Claude Code

## What this is
A governed AI gateway on Azure: apps call a model only through API Management, which authenticates them with Entra, enforces per-app token quotas, screens prompts through two layers (Content Safety Prompt Shields, then Leighton's judge from ai-firewall / llm-honeypot), and logs everything to Microsoft Sentinel. Public portfolio repo under LeightonSec.

## Source of truth
- `DECISIONS.md`: every architectural decision and its status.
- `THREAT_MODEL.md`: threats, mitigations and the test that proves each one.
If code and these files disagree, the files win. Raise the conflict; don't resolve it silently.

Local background notes may exist outside version control. They predate the decisions log and are partly out of date. Where they disagree with DECISIONS.md, the decisions log wins. Never copy content from untracked or ignored files into tracked files.

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
6. **No `terraform apply` or `destroy` from a local machine** unless Leighton explicitly says so for that run. Read-only `az` and `terraform plan` are fine.
7. **Not sure? Ask.** Don't guess at Azure behaviour; check the docs or run a read-only command, and say which you did.

## Current phase
Phase 1: Foundations. Gate criteria are at the bottom of `DECISIONS.md`.

## First task (read-only, no code)
Resolve the OPEN items in D4 and D5:
1. List chat models available for deployment in Sweden Central, and the smallest suitable current one.
2. For two or three candidate DR regions, check the same model, API Management v2 tiers and Content Safety Prompt Shields are available.
3. Report findings with the commands you ran and their output. Do not edit `DECISIONS.md`: Leighton locks decisions.
