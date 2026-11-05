#!/usr/bin/env bash
# Configures the GitHub side of D7. Run only by Leighton, interactively, from
# his own gh session (CLAUDE.md rule 6). Stores nothing locally.
#
# Steps, in order, stopping at the first failure (rule 4: fail closed):
#   0. Confirm gh is acting as LeightonSec (more than one account is logged in).
#   1. Confirm the `azure` environment exists with exactly the expected reviewer,
#      a main-only branch policy and administrator bypass off (created once by
#      hand, see bootstrap/README.md).
#   2. Compare the federated credential's subject in Azure with the subject
#      GitHub reports for this repo. Nothing is written if they differ.
#   3. Store the three IDs as environment secrets (masked in public logs).
#   4. Read back the secret names.
#
# Every gh call names the repo explicitly, so it can never act on another repo.

set -euo pipefail

REPO="LeightonSec/gatehouse"
ENVIRONMENT="azure"

cd "$(dirname "$0")/.."

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for cmd in gh az terraform jq; do
  command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not found"
done

# More than one gh account is logged in on this Mac, and every call below acts
# as the active one, so it must be the expected account.
EXPECTED_GH_LOGIN="LeightonSec"
GH_LOGIN="$(gh api user --jq .login)" || fail "cannot read the active gh account"
[[ "$GH_LOGIN" == "$EXPECTED_GH_LOGIN" ]] || fail "active gh account is '$GH_LOGIN', expected '$EXPECTED_GH_LOGIN' (run: gh auth switch)"
echo "PASS: gh is acting as $EXPECTED_GH_LOGIN"

tf_out() {
  local value
  value="$(terraform -chdir=bootstrap output -raw "$1")" || fail "cannot read output $1"
  [[ -n "$value" ]] || fail "output $1 is empty"
  printf '%s' "$value"
}

GUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

CLIENT_ID="$(tf_out deploy_client_id)"
TENANT_ID="$(tf_out tenant_id)"
SUBSCRIPTION_ID="$(tf_out subscription_id)"
BOOTSTRAP_RG="$(tf_out bootstrap_resource_group_name)"
DEPLOY_NAME="$(tf_out deploy_identity_name)"
FIC_NAME="$(tf_out federated_credential_name)"

for pair in "deploy_client_id:$CLIENT_ID" "tenant_id:$TENANT_ID" "subscription_id:$SUBSCRIPTION_ID"; do
  [[ "${pair#*:}" =~ $GUID_RE ]] || fail "${pair%%:*} is not a GUID"
done

# 1. The environment exists and is protected.
ENV_JSON="$(gh api "repos/$REPO/environments/$ENVIRONMENT")" || fail "environment '$ENVIRONMENT' not found on $REPO; create it first"
EXPECTED_REVIEWER="LeightonSec"

# Item 10: exactly one reviewers rule, exactly one reviewer, the expected
# user, and self-review allowed (he is the sole reviewer, D7).
REVIEWER_RULES="$(jq -c '[.protection_rules[]? | select(.type == "required_reviewers")]' <<<"$ENV_JSON")"
[[ "$(jq 'length' <<<"$REVIEWER_RULES")" == "1" ]] || fail "environment '$ENVIRONMENT' must have exactly one required-reviewers rule"
REVIEWERS="$(jq -r '[.[0].reviewers[] | "\(.type)|\(.reviewer.login)"] | sort | join(",")' <<<"$REVIEWER_RULES")"
[[ "$REVIEWERS" == "User|$EXPECTED_REVIEWER" ]] || fail "required reviewers are '$REVIEWERS', expected 'User|$EXPECTED_REVIEWER'"
SELF_REVIEW="$(jq -r '.[0].prevent_self_review' <<<"$REVIEWER_RULES")"
[[ "$SELF_REVIEW" == "false" ]] || fail "prevent_self_review is '$SELF_REVIEW', expected 'false'"
echo "PASS: the only required reviewer is $EXPECTED_REVIEWER, and self-review is allowed"

# Item 9: custom branch policies only, and exactly one: the branch `main`.
jq -e '.deployment_branch_policy.protected_branches == false and .deployment_branch_policy.custom_branch_policies == true' <<<"$ENV_JSON" >/dev/null \
  || fail "environment '$ENVIRONMENT' must use custom branch policies only"
BRANCHES="$(gh api "repos/$REPO/environments/$ENVIRONMENT/deployment-branch-policies" \
  --jq '[.branch_policies[] | "\(.type)|\(.name)"] | sort | join(",")')" \
  || fail "cannot read the environment's branch policies"
[[ "$BRANCHES" == "branch|main" ]] || fail "branch policies are '$BRANCHES', expected 'branch|main'"
echo "PASS: environment '$ENVIRONMENT' can only be used from main"

# Administrators can't bypass the environment's rules (D7). A missing field
# reads as null and fails closed.
ADMIN_BYPASS="$(jq -r '.can_admins_bypass' <<<"$ENV_JSON")"
[[ "$ADMIN_BYPASS" == "false" ]] || fail "can_admins_bypass is '$ADMIN_BYPASS', expected 'false'"
echo "PASS: administrators can't bypass environment '$ENVIRONMENT'"

# 2. Subject check, before anything is written.
SUB_JSON="$(gh api "repos/$REPO/actions/oidc/customization/sub")" || fail "cannot read the repo's OIDC subject settings"
PREFIX="$(jq -r '.sub_claim_prefix // empty' <<<"$SUB_JSON")"
[[ -n "$PREFIX" ]] || fail "GitHub did not report a sub_claim_prefix"
EXPECTED_SUBJECT="$PREFIX:environment:$ENVIRONMENT"

ACTUAL_SUBJECT="$(az identity federated-credential show \
  --name "$FIC_NAME" \
  --identity-name "$DEPLOY_NAME" \
  --resource-group "$BOOTSTRAP_RG" \
  --subscription "$SUBSCRIPTION_ID" \
  --query subject -o tsv)" || fail "cannot read the federated credential from Azure"

if [[ "$ACTUAL_SUBJECT" != "$EXPECTED_SUBJECT" ]]; then
  echo "GitHub expects: $EXPECTED_SUBJECT" >&2
  echo "Azure has:      $ACTUAL_SUBJECT" >&2
  fail "federated credential subject does not match what GitHub reports"
fi
echo "PASS: federated credential subject matches what GitHub reports"

# 3. Store the IDs as environment secrets. Values go in on stdin, so they never
#    appear in the process list or shell history.
set_secret() {
  printf '%s' "$2" | gh secret set "$1" --env "$ENVIRONMENT" --repo "$REPO" >/dev/null \
    || fail "could not set secret $1"
}
set_secret AZURE_CLIENT_ID "$CLIENT_ID"
set_secret AZURE_TENANT_ID "$TENANT_ID"
set_secret AZURE_SUBSCRIPTION_ID "$SUBSCRIPTION_ID"

# 4. Read back the names (GitHub never returns secret values).
NAMES="$(gh secret list --env "$ENVIRONMENT" --repo "$REPO" --json name --jq '.[].name')" \
  || fail "could not list environment secrets"
for name in AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID; do
  grep -qx "$name" <<<"$NAMES" || fail "secret $name missing after setting it"
done
echo "PASS: the three environment secrets are set"

echo "GitHub configuration complete."
