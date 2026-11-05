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

## Current task: take the bootstrap to a verified apply (Leighton applies)
State on 2026-11-05: the bootstrap is committed (9d67c75), and so is the hardening (b09f527 decisions, b044120 code). Nothing has been applied to Azure.

Remaining, in order. Steps marked (L) are Leighton's alone. You prepare the commands and check the output.
1. Signature checks (D6), all (L): `codesign` and `spctl` on the installed Terraform, in his own shell; gnupg after its soak check; HashiCorp's key fingerprint compared against two HashiCorp pages, never taken from memory; `gpg --verify` on Terraform's SHA256SUMS and both providers' SHA256SUMS. Download the files into a temporary folder, never into the repo.
2. Register `Microsoft.Storage` and `Microsoft.ManagedIdentity` (L). Create `bootstrap/terraform.tfvars` from the example (L). Never read, print or copy its values.
3. Plan (L): `CHECKPOINT_DISABLE=1`, `init -lockfile=readonly`, then `plan`. Share a summary only, and never save a plan file (rule 8). The role postcondition runs here for the first time.
4. Apply (L, rule 6). Then `bash scripts/verify-bootstrap.sh` (L). Fix any expected-value mismatch with a reviewed edit, never by loosening a check. Then an encrypted backup of the state, outside the Mac (L).
5. Create the `azure` environment as `bootstrap/README.md` describes (L). Before relying on the admin-bypass check, confirm `can_admins_bypass` appears in the environment's API response; if it doesn't, stop and report. Then `bash scripts/configure-github.sh` (L).
6. Then the CI pipeline (D7), including D6's CI supply-chain checks from the Phase 1 gate.

Standing rules for this work: every `!` command fits on one terminal line; the scripts stay mode 100644 and run with `bash`; Terraform never runs with sudo.
