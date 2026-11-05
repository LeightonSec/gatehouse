#!/usr/bin/env bash
# Read-only checks after each bootstrap apply (D6, T13, T17).
# Run by Leighton from the repo root or anywhere: it changes nothing in Azure.
#
# Checks:
#   1. The CLI is on the subscription the bootstrap targeted.
#   2. The deploy identity has exactly one federated credential, with the
#      expected issuer, audience and subject.
#   3. No app identity has any federated credential.
#   4. The deploy identity holds exactly the expected role assignments,
#      including anything inherited from the subscription, and the RBAC
#      Administrator condition matches the one the bootstrap built.
#   4b. The deploy identity holds no API permissions, directory roles or
#       group memberships.
#   5. The gateway's `invoke` role is held by exactly the three app
#      identities, and assignment is required.
#   6. The gateway app is single-tenant, holds no credentials with its
#      service principal, and defines exactly one role, `invoke`.
#   7. The state storage settings match their exact expected values.
# Every check compares against an exact expected value. Any mismatch or
# error exits non-zero (rule 4: fail closed).

set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for cmd in az terraform jq; do
  command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not found"
done

expect() {
  # expect <label> <actual> <expected>
  [[ "$2" == "$3" ]] || fail "$1 is '$2', expected '$3'"
}

tf_out() {
  local value
  value="$(terraform -chdir=bootstrap output -raw "$1")" || fail "cannot read output $1"
  [[ -n "$value" ]] || fail "output $1 is empty"
  printf '%s' "$value"
}

SUBSCRIPTION_ID="$(tf_out subscription_id)"
BOOTSTRAP_RG="$(tf_out bootstrap_resource_group_name)"
DEPLOY_NAME="$(tf_out deploy_identity_name)"
DEPLOY_PRINCIPAL_ID="$(tf_out deploy_principal_id)"
EXPECTED_SUBJECT="$(tf_out federated_subject)"
STACK_RG_ID="$(tf_out stack_resource_group_id)"
STATE_CONTAINER_ID="$(tf_out state_container_id)"
APP_IDENTITIES_JSON="$(terraform -chdir=bootstrap output -json app_identities)" || fail "cannot read output app_identities"

# 1. Right subscription.
CLI_SUBSCRIPTION="$(az account show --query id -o tsv)" || fail "az account show failed"
[[ "$CLI_SUBSCRIPTION" == "$SUBSCRIPTION_ID" ]] || fail "az CLI is on a different subscription than the bootstrap"
echo "PASS: az CLI is on the bootstrap's subscription"

# 2. Exactly one federated credential on the deploy identity, matching what was built.
FICS="$(az identity federated-credential list \
  --identity-name "$DEPLOY_NAME" \
  --resource-group "$BOOTSTRAP_RG" \
  --subscription "$SUBSCRIPTION_ID" \
  -o json)" || fail "cannot list federated credentials on the deploy identity"

[[ "$(jq 'length' <<<"$FICS")" == "1" ]] || fail "deploy identity must have exactly one federated credential, found $(jq 'length' <<<"$FICS")"
[[ "$(jq -r '.[0].subject' <<<"$FICS")" == "$EXPECTED_SUBJECT" ]] || fail "federated credential subject does not match the subject built from tfvars"
[[ "$(jq -r '.[0].issuer' <<<"$FICS")" == "https://token.actions.githubusercontent.com" ]] || fail "unexpected federated credential issuer"
[[ "$(jq -c '.[0].audiences' <<<"$FICS")" == '["api://AzureADTokenExchange"]' ]] || fail "unexpected federated credential audience"
echo "PASS: deploy identity has one federated credential with the expected subject, issuer and audience"

# 3. No federated credentials on any app identity.
while IFS= read -r app_id; do
  app_name="${app_id##*/}"
  count="$(az identity federated-credential list \
    --identity-name "$app_name" \
    --resource-group "$BOOTSTRAP_RG" \
    --subscription "$SUBSCRIPTION_ID" \
    --query 'length(@)' -o tsv)" || fail "cannot list federated credentials on $app_name"
  [[ "$count" == "0" ]] || fail "$app_name has $count federated credential(s); it must have none"
done < <(jq -r '.[].id' <<<"$APP_IDENTITIES_JSON")
echo "PASS: no app identity has a federated credential"

# 4. Exactly the expected role assignments, including inherited ones.
lower() { tr '[:upper:]' '[:lower:]'; }

EXPECTED_ROLES="$(
  {
    echo "Contributor|$STACK_RG_ID"
    echo "Role Based Access Control Administrator|$STACK_RG_ID"
    echo "Storage Blob Data Contributor|$STATE_CONTAINER_ID"
    jq -r '.[].id | "Managed Identity Operator|" + .' <<<"$APP_IDENTITIES_JSON"
  } | lower | sort
)"

ASSIGNMENTS="$(az role assignment list \
  --assignee "$DEPLOY_PRINCIPAL_ID" \
  --all \
  --include-inherited \
  --subscription "$SUBSCRIPTION_ID" \
  -o json)" || fail "cannot list the deploy identity's role assignments"

ACTUAL_ROLES="$(jq -r '.[] | "\(.roleDefinitionName)|\(.scope)"' <<<"$ASSIGNMENTS" | lower | sort)"

if [[ "$ACTUAL_ROLES" != "$EXPECTED_ROLES" ]]; then
  echo "Expected:" >&2
  echo "$EXPECTED_ROLES" >&2
  echo "Actual:" >&2
  echo "$ACTUAL_ROLES" >&2
  fail "the deploy identity's role assignments differ from the expected set"
fi

echo "PASS: deploy identity holds exactly the expected role assignments"

# This compares Azure with what Terraform built, so it catches drift or
# tampering in Azure, not a badly designed condition: the design is checked
# in Leighton's line-by-line review (T17). Whitespace isn't significant in a
# condition, so compare with all of it removed.
squash() { tr -d '[:space:]'; }
EXPECTED_CONDITION="$(terraform -chdir=bootstrap output -raw rbac_admin_condition | squash)" || fail "cannot read output rbac_admin_condition"
[[ -n "$EXPECTED_CONDITION" ]] || fail "output rbac_admin_condition is empty"
RBAC_ADMIN="$(jq -c '[.[] | select(.roleDefinitionName == "Role Based Access Control Administrator")][0]' <<<"$ASSIGNMENTS")"
expect "RBAC Administrator condition" "$(jq -r '.condition // ""' <<<"$RBAC_ADMIN" | squash)" "$EXPECTED_CONDITION"
expect "RBAC Administrator condition version" "$(jq -r '.conditionVersion // ""' <<<"$RBAC_ADMIN")" "2.0"
echo "PASS: the RBAC Administrator condition matches the one the bootstrap built"

# 4b. No API permissions, directory roles or group memberships (D7, T13).
GRAPH_ROLES="$(az rest --method get --url "https://graph.microsoft.com/v1.0/servicePrincipals/$DEPLOY_PRINCIPAL_ID/appRoleAssignments" -o json)" \
  || fail "cannot read the deploy identity's app role assignments"
expect "deploy identity app role assignments" "$(jq -c '.value' <<<"$GRAPH_ROLES")" "[]"
MEMBER_OF="$(az rest --method get --url "https://graph.microsoft.com/v1.0/servicePrincipals/$DEPLOY_PRINCIPAL_ID/memberOf" -o json)" \
  || fail "cannot read the deploy identity's directory roles and groups"
expect "deploy identity directory roles and groups" "$(jq -c '.value' <<<"$MEMBER_OF")" "[]"
echo "PASS: the deploy identity holds no API permissions, directory roles or group memberships"

# 5. The gateway's `invoke` role: held by exactly the three app identities.
GATEWAY_CLIENT_ID="$(tf_out gateway_client_id)"
GATEWAY_SP_ID="$(tf_out gateway_service_principal_object_id)"
INVOKE_ROLE_ID="$(tf_out gateway_invoke_role_id)"

EXPECTED_GRANTS="$(jq -r --arg r "$INVOKE_ROLE_ID" '.[].principal_id + "|" + $r' <<<"$APP_IDENTITIES_JSON" | lower | sort)"
GRANTS="$(az rest --method get \
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/$GATEWAY_SP_ID/appRoleAssignedTo" \
  -o json)" || fail "cannot list who holds roles on the gateway"
expect "gateway role assignment paging" "$(jq -r '."@odata.nextLink" // ""' <<<"$GRANTS")" ""
ACTUAL_GRANTS="$(jq -r '.value[] | .principalId + "|" + .appRoleId' <<<"$GRANTS" | lower | sort)"
if [[ "$ACTUAL_GRANTS" != "$EXPECTED_GRANTS" ]]; then
  echo "Expected (principal|role):" >&2
  echo "$EXPECTED_GRANTS" >&2
  echo "Actual (principal|role):" >&2
  echo "$ACTUAL_GRANTS" >&2
  fail "the gateway's role holders differ from the three app identities"
fi

SP_JSON="$(az ad sp show --id "$GATEWAY_SP_ID" -o json)" || fail "cannot read the gateway service principal"
expect "gateway appRoleAssignmentRequired" "$(jq -r '.appRoleAssignmentRequired' <<<"$SP_JSON")" "true"
echo "PASS: invoke is held by exactly the three app identities, and assignment is required"

# 6. No credentials on the gateway app or its service principal; one role only.
APP_JSON="$(az ad app show --id "$GATEWAY_CLIENT_ID" -o json)" || fail "cannot read the gateway app registration"
expect "gateway app password credentials" "$(jq -c '.passwordCredentials' <<<"$APP_JSON")" "[]"
expect "gateway app key credentials" "$(jq -c '.keyCredentials' <<<"$APP_JSON")" "[]"
FED_JSON="$(az ad app federated-credential list --id "$GATEWAY_CLIENT_ID" -o json)" || fail "cannot list the gateway app's federated credentials"
expect "gateway app federated credentials" "$(jq -c '.' <<<"$FED_JSON")" "[]"
expect "gateway service principal password credentials" "$(jq -c '.passwordCredentials' <<<"$SP_JSON")" "[]"
expect "gateway service principal key credentials" "$(jq -c '.keyCredentials' <<<"$SP_JSON")" "[]"
expect "gateway app roles" \
  "$(jq -c '[.appRoles[] | {id, value, allowedMemberTypes, isEnabled}]' <<<"$APP_JSON")" \
  "[{\"id\":\"$INVOKE_ROLE_ID\",\"value\":\"invoke\",\"allowedMemberTypes\":[\"Application\"],\"isEnabled\":true}]"
expect "gateway signInAudience" "$(jq -r '.signInAudience' <<<"$APP_JSON")" "AzureADMyOrg"
echo "PASS: the gateway app is single-tenant, holds no credentials with its service principal, and defines only the invoke role"

# 7. State storage settings, each against its exact expected value.
STATE_BACKEND_JSON="$(terraform -chdir=bootstrap output -json state_backend)" || fail "cannot read output state_backend"
STATE_ACCOUNT="$(jq -r '.storage_account_name' <<<"$STATE_BACKEND_JSON")"
STATE_CONTAINER="$(jq -r '.container_name' <<<"$STATE_BACKEND_JSON")"

SA_JSON="$(az storage account show --name "$STATE_ACCOUNT" --resource-group "$BOOTSTRAP_RG" --subscription "$SUBSCRIPTION_ID" -o json)" \
  || fail "cannot read the state storage account"
expect "state account kind"                       "$(jq -r '.kind' <<<"$SA_JSON")"                                  "StorageV2"
expect "state account sku"                        "$(jq -r '.sku.name' <<<"$SA_JSON")"                              "Standard_ZRS"
expect "state account allowBlobPublicAccess"      "$(jq -r '.allowBlobPublicAccess' <<<"$SA_JSON")"                 "false"
expect "state account allowSharedKeyAccess"       "$(jq -r '.allowSharedKeyAccess' <<<"$SA_JSON")"                  "false"
expect "state account defaultToOAuthAuthentication" "$(jq -r '.defaultToOAuthAuthentication' <<<"$SA_JSON")"        "true"
expect "state account minimumTlsVersion"          "$(jq -r '.minimumTlsVersion' <<<"$SA_JSON")"                     "TLS1_2"
expect "state account enableHttpsTrafficOnly"     "$(jq -r '.enableHttpsTrafficOnly' <<<"$SA_JSON")"                "true"
expect "state account allowCrossTenantReplication" "$(jq -r '.allowCrossTenantReplication' <<<"$SA_JSON")"          "false"
expect "state account isLocalUserEnabled"         "$(jq -r '.isLocalUserEnabled' <<<"$SA_JSON")"                    "false"
expect "state account isSftpEnabled"              "$(jq -r '.isSftpEnabled' <<<"$SA_JSON")"                         "false"
expect "state account requireInfrastructureEncryption" "$(jq -r '.encryption.requireInfrastructureEncryption' <<<"$SA_JSON")" "true"
expect "state account publicNetworkAccess"        "$(jq -r '.publicNetworkAccess' <<<"$SA_JSON")"                   "Enabled"

BLOB_JSON="$(az storage account blob-service-properties show --account-name "$STATE_ACCOUNT" --resource-group "$BOOTSTRAP_RG" --subscription "$SUBSCRIPTION_ID" -o json)" \
  || fail "cannot read the state account's blob service properties"
expect "state blob versioning"               "$(jq -r '.isVersioningEnabled' <<<"$BLOB_JSON")"                   "true"
expect "state blob soft delete"              "$(jq -r '.deleteRetentionPolicy.enabled' <<<"$BLOB_JSON")"         "true"
expect "state blob soft delete days"         "$(jq -r '.deleteRetentionPolicy.days' <<<"$BLOB_JSON")"            "30"
expect "state container soft delete"         "$(jq -r '.containerDeleteRetentionPolicy.enabled' <<<"$BLOB_JSON")" "true"
expect "state container soft delete days"    "$(jq -r '.containerDeleteRetentionPolicy.days' <<<"$BLOB_JSON")"   "30"

CONTAINER_JSON="$(az storage container-rm show --storage-account "$STATE_ACCOUNT" --resource-group "$BOOTSTRAP_RG" --subscription "$SUBSCRIPTION_ID" --name "$STATE_CONTAINER" -o json)" \
  || fail "cannot read the state container"
expect "state container public access" "$(jq -r '.publicAccess' <<<"$CONTAINER_JSON")" "None"
echo "PASS: state storage settings match their expected values"

echo "All bootstrap checks passed."
