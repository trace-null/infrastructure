#!/usr/bin/env bash
# scripts/openbao-configure.sh
#
# First-time configuration of a freshly initialised OpenBao. It checks that
# the audit log is active, then sets up the secret store, policies, AppRoles
# for Ansible and OpenTofu and an admin user, and finally revokes the root
# token. Run it with:  just openbao-configure
#
# Safe to run again. Anything already there is left alone, and existing
# Bitwarden credentials are not replaced.

set -euo pipefail
# shellcheck source=openbao-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/openbao-lib.sh"

need_tools bao bw jq openssl

ITEM_ROOT="${ITEM_OPENBAO_ROOT:-infrastructure/openbao-root-token}"
ITEM_ADMIN="${ITEM_OPENBAO_ADMIN:-infrastructure/openbao-admin}"
ITEM_ANSIBLE="${ITEM_OPENBAO_APPROLE_ANSIBLE:-infrastructure/openbao-approle-ansible}"
ITEM_TOFU="${ITEM_OPENBAO_APPROLE_TOFU:-infrastructure/openbao-approle-tofu}"

openbao_env

if [[ "$(bw_count "${ITEM_ROOT}")" == 0 ]]; then
  die "No root token in Bitwarden. It is only there between init and configure. If it was already revoked, OpenBao is configured. To get a root token again, use the recovery keys: bao operator generate-root"
fi
root_token="$(bw get password "${ITEM_ROOT}")"
export BAO_TOKEN="${root_token}"
bao token lookup > /dev/null || die "The root token from Bitwarden is not valid."

info "Audit log"
if bao audit list -format=json | jq -e 'has("file/")' > /dev/null; then
  echo "  active"
else
  die "The audit device is not active. It is declared in the OpenBao config, so check that the config was applied and the service restarted."
fi

info "Secret store"
if bao secrets list -format=json | jq -e 'has("secret/")' > /dev/null; then
  echo "  already enabled"
else
  bao secrets enable -path=secret -version=2 kv > /dev/null
fi

info "Policies"
bao policy write ansible - > /dev/null <<'POLICY'
# Ansible reads secrets for the things it deploys.
path "secret/data/apps/*"          { capabilities = ["read"] }
path "secret/metadata/apps/*"      { capabilities = ["read", "list"] }
path "secret/data/generated/*"     { capabilities = ["read"] }
path "secret/metadata/generated/*" { capabilities = ["read", "list"] }
POLICY

bao policy write tofu - > /dev/null <<'POLICY'
# OpenTofu writes the secrets it generates.
path "secret/data/generated/*"     { capabilities = ["create", "read", "update", "delete"] }
path "secret/metadata/generated/*" { capabilities = ["read", "list", "delete"] }
POLICY

bao policy write admin - > /dev/null <<'POLICY'
# Day-to-day administration without the root token. It cannot change audit
# devices, seal or unseal, or reach the raw storage.
path "secret/*"           { capabilities = ["create", "read", "update", "patch", "delete", "list"] }
path "sys/policies/acl"   { capabilities = ["list"] }
path "sys/policies/acl/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "sys/auth"           { capabilities = ["read"] }
path "sys/auth/*"         { capabilities = ["create", "read", "update", "delete", "sudo"] }
path "auth/*"             { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "sys/mounts"         { capabilities = ["read"] }
path "sys/mounts/*"       { capabilities = ["create", "read", "update", "delete"] }
path "sys/leases/*"       { capabilities = ["read", "list", "update"] }
path "identity/*"         { capabilities = ["create", "read", "update", "delete", "list"] }
POLICY

info "Login methods"
for method in approle userpass; do
  if bao auth list -format=json | jq -e --arg m "${method}/" 'has($m)' > /dev/null; then
    echo "  ${method} already enabled"
  else
    bao auth enable "${method}" > /dev/null
  fi
done

info "AppRoles for Ansible and OpenTofu"
for role in ansible tofu; do
  bao write "auth/approle/role/${role}" token_policies="${role}" \
    token_ttl=15m token_max_ttl=1h secret_id_ttl=0 secret_id_num_uses=0 > /dev/null
done

create_approle_item() { # <role> <bitwarden item>
  local role="$1" item="$2" role_id secret_id
  if [[ "$(bw_count "${item}")" != 0 ]]; then
    echo "  ${item} already exists, leaving it as it is"
    return
  fi
  role_id="$(bao read -field=role_id "auth/approle/role/${role}/role-id")"
  secret_id="$(bao write -f -field=secret_id "auth/approle/role/${role}/secret-id")"
  bw_create "${item}" login "AppRole for ${role}. The username is the role ID and the password is the secret ID." "${secret_id}" "${role_id}"
  echo "  saved ${item}"
}
create_approle_item ansible "${ITEM_ANSIBLE}"
create_approle_item tofu "${ITEM_TOFU}"

info "Admin user"
if [[ "$(bw_count "${ITEM_ADMIN}")" != 0 ]]; then
  echo "  ${ITEM_ADMIN} already exists, leaving it as it is"
else
  admin_password="$(openssl rand -base64 24 | tr -d '\n')"
  printf '%s' "${admin_password}" | bao write auth/userpass/users/admin password=- policies=admin > /dev/null
  bw_create "${ITEM_ADMIN}" login "OpenBao admin. Log in with: bao login -method=userpass username=admin" "${admin_password}" "admin"
  echo "  saved ${ITEM_ADMIN}"
fi
bw sync > /dev/null 2>&1 || true

info "Checking that the new logins work and are limited"
expect_caps() { # <token> <path> <capability that must be listed> <description>
  local caps
  caps="$(BAO_TOKEN="$1" bao token capabilities "$2" 2> /dev/null || true)"
  [[ "${caps}" == *"$3"* ]] || die "Check failed: $4 (got '${caps}')"
}
expect_no_caps() { # <token> <path> <capability that must not be listed> <description>
  local caps
  caps="$(BAO_TOKEN="$1" bao token capabilities "$2" 2> /dev/null || true)"
  [[ "${caps}" != *"$3"* ]] || die "Check failed: $4 (got '${caps}')"
}
approle_token() { # <bitwarden item>
  local rid sid
  rid="$(bw get username "$1")"
  sid="$(bw get password "$1")"
  printf '%s' "${sid}" | bao write -field=token auth/approle/login role_id="${rid}" secret_id=-
}
ansible_token="$(approle_token "${ITEM_ANSIBLE}")"
tofu_token="$(approle_token "${ITEM_TOFU}")"
expect_caps    "${ansible_token}" secret/data/apps/example read "ansible can read apps"
expect_no_caps "${ansible_token}" secret/data/apps/example update "ansible cannot write apps"
expect_no_caps "${ansible_token}" secret/data/apps/example create "ansible cannot create apps"
expect_caps    "${ansible_token}" sys/policies/acl/admin deny "ansible cannot read policies"
expect_caps    "${tofu_token}" secret/data/generated/example create "tofu can write generated secrets"
expect_caps    "${tofu_token}" secret/data/apps/example deny "tofu cannot touch apps"
admin_password="$(bw get password "${ITEM_ADMIN}")"
admin_token="$(printf '%s' "${admin_password}" | bao write -field=token auth/userpass/login/admin password=-)"
expect_caps    "${admin_token}" sys/policies/acl/ansible read "admin can manage policies"
expect_caps    "${admin_token}" sys/audit/file deny "admin cannot change audit devices"

info "Revoking the root token"
bao token revoke -self > /dev/null
if BAO_TOKEN="${root_token}" bao token lookup > /dev/null 2>&1; then
  die "The root token still works after revoking it."
fi
bw_delete "${ITEM_ROOT}"

cat <<EOF

OpenBao is configured and the root token is revoked.
Saved in Bitwarden:
  ${ITEM_ADMIN}    (log in: bao login -method=userpass username=admin)
  ${ITEM_ANSIBLE}
  ${ITEM_TOFU}

To get a root token again, use the recovery keys: bao operator generate-root
EOF
