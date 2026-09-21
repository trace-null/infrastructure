#!/usr/bin/env bash
# scripts/openbao-snapshot-setup.sh
#
# Creates the snapshot policy and AppRole in OpenBao and saves the AppRole
# credentials in Bitwarden. It logs in as the admin user, so no root token
# is needed. Run it with:  just openbao-snapshot-setup
#
# Safe to run again. An existing Bitwarden item is left as it is.

set -euo pipefail
# shellcheck source=openbao-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/openbao-lib.sh"

need_tools bao bw jq

ITEM_ADMIN="${ITEM_OPENBAO_ADMIN:-infrastructure/openbao-admin}"
ITEM_SNAPSHOT="${ITEM_OPENBAO_APPROLE_SNAPSHOT:-infrastructure/openbao-approle-snapshot}"

openbao_env

info "Logging in as admin"
admin_password="$(bw get password "${ITEM_ADMIN}")"
BAO_TOKEN="$(printf '%s' "${admin_password}" | bao write -field=token auth/userpass/login/admin password=-)"
export BAO_TOKEN
unset admin_password
trap 'bao token revoke -self > /dev/null 2>&1 || true' EXIT

info "Snapshot policy"
bao policy write snapshot - > /dev/null <<'POLICY'
# Saving a Raft snapshot. Nothing else.
path "sys/storage/raft/snapshot" { capabilities = ["read"] }
POLICY

info "Snapshot AppRole"
bao write auth/approle/role/snapshot token_policies=snapshot \
  token_ttl=10m token_max_ttl=30m secret_id_ttl=0 secret_id_num_uses=0 > /dev/null

if [[ "$(bw_count "${ITEM_SNAPSHOT}")" != 0 ]]; then
  echo "  ${ITEM_SNAPSHOT} already exists, leaving it as it is"
else
  role_id="$(bao read -field=role_id auth/approle/role/snapshot/role-id)"
  secret_id="$(bao write -f -field=secret_id auth/approle/role/snapshot/secret-id)"
  bw_create "${ITEM_SNAPSHOT}" login "AppRole for Raft snapshots. The username is the role ID and the password is the secret ID." "${secret_id}" "${role_id}"
  bw sync > /dev/null 2>&1 || true
  echo "  saved ${ITEM_SNAPSHOT}"
fi

info "Checking that the login works and is limited"
rid="$(bw get username "${ITEM_SNAPSHOT}")"
sid="$(bw get password "${ITEM_SNAPSHOT}")"
snapshot_token="$(printf '%s' "${sid}" | bao write -field=token auth/approle/login role_id="${rid}" secret_id=-)"
caps="$(BAO_TOKEN="${snapshot_token}" bao token capabilities sys/storage/raft/snapshot 2> /dev/null || true)"
[[ "${caps}" == *read* ]] || die "Check failed: the snapshot role cannot read snapshots (got '${caps}')"
caps="$(BAO_TOKEN="${snapshot_token}" bao token capabilities secret/data/apps/example 2> /dev/null || true)"
[[ "${caps}" != *read* ]] || die "Check failed: the snapshot role can read secrets (got '${caps}')"
BAO_TOKEN="${snapshot_token}" bao token revoke -self > /dev/null

cat <<DONE

The snapshot policy and AppRole are ready.
Saved in Bitwarden:
  ${ITEM_SNAPSHOT}
DONE
