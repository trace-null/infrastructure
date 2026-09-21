#!/usr/bin/env bash
# scripts/openbao-init.sh
#
# Initialises a fresh OpenBao once and stores the recovery keys and a
# temporary root token in Bitwarden. Run it with:  just openbao-init
#
# OpenBao must already be running with the static seal, which the bootstrap
# playbook sets up. The seal key itself is not handled here.

set -euo pipefail
# shellcheck source=openbao-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/openbao-lib.sh"

need_tools bao bw jq openssl

ITEM_RECOVERY="${ITEM_OPENBAO_RECOVERY:-infrastructure/openbao-recovery-keys}"
ITEM_ROOT="${ITEM_OPENBAO_ROOT:-infrastructure/openbao-root-token}"
shares="${OPENBAO_RECOVERY_SHARES:-3}"
threshold="${OPENBAO_RECOVERY_THRESHOLD:-2}"

openbao_env

info "Checking that OpenBao is reachable and not yet initialised"
# bao status exits non-zero when sealed, but still prints JSON when reachable.
status_json="$(bao status -format=json 2> /dev/null || true)"
initialised="$(jq -r '.initialized | tostring' <<< "${status_json}" 2> /dev/null || true)"
case "${initialised}" in
  false) ;;
  true)  die "OpenBao is already initialised. Nothing to do." ;;
  *)     die "Cannot reach OpenBao at ${BAO_ADDR}. Check the tunnel, the certificate and the service." ;;
esac

if [[ "$(bw_count "${ITEM_RECOVERY}")" != 0 || "$(bw_count "${ITEM_ROOT}")" != 0 ]]; then
  die "Bitwarden already has '${ITEM_RECOVERY}' or '${ITEM_ROOT}'. Remove or rename them so nothing is overwritten."
fi

info "Initialising with ${shares} recovery shares (threshold ${threshold})"
# The output goes to memory-backed storage first, so a failure while saving to
# Bitwarden cannot lose the keys.
safety="$(mktemp "${XDG_RUNTIME_DIR:-/dev/shm}/openbao-init.XXXXXX")"
chmod 600 "${safety}"
trap 'if [[ -s "${safety}" ]]; then printf "\nThe init output is kept in %s (memory-backed). Import it into Bitwarden by hand, then delete it.\n" "${safety}" >&2; else rm -f "${safety}"; fi' ERR
bao operator init -recovery-shares="${shares}" -recovery-threshold="${threshold}" -format=json > "${safety}"

info "Saving to Bitwarden"
notes="$(jq -r --arg t "${threshold}" '
  "Recovery keys. Any \($t) of \(.recovery_keys_b64 | length) authorise privileged operations such as generating a new root token. They do not decrypt data.\n\n"
  + (.recovery_keys_b64 | join("\n"))' "${safety}")"
root_token="$(jq -r .root_token "${safety}")"

bw_create "${ITEM_RECOVERY}" note "${notes}"
bw_create "${ITEM_ROOT}" login "Temporary root token. Revoked by: just openbao-configure" "${root_token}"
bw sync > /dev/null 2>&1 || true

info "Checking what was saved"
[[ "$(bw get password "${ITEM_ROOT}")" == "${root_token}" ]] || die "The root token in Bitwarden does not match."
saved="$(bw get notes "${ITEM_RECOVERY}" | grep -c -E '^[A-Za-z0-9+/=]{20,}$' || true)"
[[ "${saved}" == "${shares}" ]] || die "Expected ${shares} recovery keys in Bitwarden, found ${saved}."

trap - ERR
shred -u "${safety}" 2> /dev/null || rm -f "${safety}"

info "Checking that OpenBao unsealed itself"
bao status -format=json | jq -e '.sealed == false' > /dev/null || die "OpenBao is still sealed. Check the seal key and the service logs."

cat <<EOF

OpenBao is initialised and unsealed.
Saved in Bitwarden:
  ${ITEM_RECOVERY}
  ${ITEM_ROOT}   (temporary)

Next: just openbao-configure
EOF
