# Bootstrap

The minimal, most privileged Terraform in Gatehouse (D6, T17). It creates what CI cannot create for itself. It is the only Terraform applied from a local machine, and only Leighton applies it, after a line-by-line review.

State is local and gitignored. Keep an encrypted copy outside the Mac after each apply.

## What it creates

### Resource groups
| Name | Purpose |
| --- | --- |
| `rg-gatehouse-bootstrap` | State account, deploy identity, app identities. The deploy identity has no control rights here except Managed Identity Operator on each app identity. |
| `rg-gatehouse` | Where CI deploys the main stack. |

### In `rg-gatehouse-bootstrap`
| Resource | Notes |
| --- | --- |
| Storage account (name from tfvars) | ZRS, TLS 1.2, infrastructure encryption, versioning, 30-day blob and container soft delete. No anonymous access, no account keys, no key-based SAS (an identity with blob data rights can still create a user delegation SAS through Entra), no local users, no SFTP. `prevent_destroy` set. Endpoint reachable (GitHub-hosted runners need it); private networking deferred (D12). |
| Container `tfstate` | Private. Main stack state. |
| Managed identity `id-gatehouse-deploy` | CI's deploy identity (D7). |
| Federated credential `github-environment-azure` | On the deploy identity. Issuer `https://token.actions.githubusercontent.com`, audience `api://AzureADTokenExchange`, subject `repo:<owner>@<owner_id>/<repo>@<repo_id>:environment:azure`. The only federated credential in the project. |
| Managed identities `id-gatehouse-app-hr`, `-support`, `-code` | One per simulated app (D8). No federated credentials. |

### In Entra
| Object | Notes |
| --- | --- |
| App registration `gatehouse-gateway` | The token audience for the apps (D8). Single-tenant, v2 tokens. One app role: `invoke` (applications only). Owner: whoever applies. |
| Service principal for it | Assignment required. |
| App role assignments | `invoke` granted to each of the three app identities. Nothing else. |

### Role assignments held by the deploy identity
Exactly these, and nothing at subscription scope. `scripts/verify-bootstrap.sh` fails on any difference, including inherited assignments.

| Role | Scope | Why |
| --- | --- | --- |
| Contributor | `rg-gatehouse` | Deploy the main stack. |
| Role Based Access Control Administrator, with condition | `rg-gatehouse` | Grant only the roles named in `rbac.tf` (Cognitive Services OpenAI User, D4), only to service principals (D7). |
| Storage Blob Data Contributor | the `tfstate` container | Main stack state. Data access only, no control of the account. |
| Managed Identity Operator | each app identity, separately | Attach app identities to their containers. Never on the resource group, which also holds the deploy identity. |

## Prerequisites
- `az login` to the right tenant, as a user who can create resource groups and role assignments in the subscription (Owner) and create app registrations and grant app roles in Entra.
- Resource providers `Microsoft.Storage` and `Microsoft.ManagedIdentity` registered. The azurerm provider doesn't auto-register: `providers.tf` sets `resource_provider_registrations = "none"` explicitly (also the 5.11.0 default). Check: `az provider show -n Microsoft.Storage --query registrationState -o tsv`.
- `terraform.tfvars` created from `terraform.tfvars.example`.
- The repo folder readable only by you (`chmod 700`). Never run Terraform with sudo (D6).
- `export CHECKPOINT_DISABLE=1` in your shell, so Terraform doesn't contact HashiCorp on every run (D6).
- The Terraform binary verified against HashiCorp's signed SHA256SUMS (D6).

## Steps (Leighton only)
1. `terraform -chdir=bootstrap init -lockfile=readonly` (the lock file is committed; init must not change it)
2. `terraform -chdir=bootstrap plan`, then review. Never save the plan file in the repo (CLAUDE.md rule 8).
3. `terraform -chdir=bootstrap apply`
4. `bash scripts/verify-bootstrap.sh`: must print "All bootstrap checks passed."
5. First time only: create the `azure` environment (below).
6. `bash scripts/configure-github.sh`: must print "GitHub configuration complete."
7. Back up `bootstrap/terraform.tfstate`, encrypted, outside the Mac.

## Creating the `azure` environment (once, by hand)
Required reviewer: Leighton. Branch policy: `main` only. Prevent self-review: off (sole reviewer). Administrator bypass: off. Check these calls against GitHub's REST docs before running them.

```bash
REVIEWER_ID="$(gh api user --jq .id)"
gh api -X PUT repos/LeightonSec/gatehouse/environments/azure --input - <<EOF
{"reviewers":[{"type":"User","id":$REVIEWER_ID}],"prevent_self_review":false,"can_admins_bypass":false,"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
EOF
gh api -X POST repos/LeightonSec/gatehouse/environments/azure/deployment-branch-policies -f name=main -f type=branch
```

The environment survives Azure rebuilds. A DR drill only reruns steps 1 to 4, 6 and 7.
