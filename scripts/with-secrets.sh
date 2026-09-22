#!/usr/bin/env bash
# scripts/with-secrets.sh
#
# Runs a command with secrets from Bitwarden loaded into its environment.
# Nothing is written to disk and the values exist only for that command.
#
# Usage: scripts/with-secrets.sh <command> [args...]
#
# Unlock Bitwarden once per shell first:
#   export BW_SESSION="$(bw unlock --raw)"
# If you add or change items in Bitwarden, run `bw sync` before using this.

set -euo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ $# -gt 0 ]] || die "Usage: $0 <command> [args...]"
command -v bw >/dev/null 2>&1 || die "The Bitwarden CLI (bw) is not installed. Run: just setup"
[[ -n "${BW_SESSION:-}" ]] || die 'Bitwarden is locked. Run: export BW_SESSION="$(bw unlock --raw)"'

# Bitwarden item names. Override them in .env if yours differ.
ITEM_PROXMOX_TOKEN="${ITEM_PROXMOX_TOKEN:-infrastructure/proxmox-api-token}"
ITEM_STATE_PASSPHRASE="${ITEM_STATE_PASSPHRASE:-infrastructure/tofu-state-passphrase}"

# Proxmox API token, in the form user@realm!tokenid=secret
PROXMOX_VE_API_TOKEN="$(bw get password "${ITEM_PROXMOX_TOKEN}")" \
  || die "Could not read '${ITEM_PROXMOX_TOKEN}' from Bitwarden."
export PROXMOX_VE_API_TOKEN

# OpenTofu state and plan encryption. The passphrase never appears in the repo.
state_pass="$(bw get password "${ITEM_STATE_PASSPHRASE}")" \
  || die "Could not read '${ITEM_STATE_PASSPHRASE}' from Bitwarden."
[[ "${state_pass}" =~ ^[A-Za-z0-9_-]{16,}$ ]] \
  || die "The state passphrase needs at least 16 characters (letters, digits, _ or -)."

TF_ENCRYPTION="$(cat <<ENC
key_provider "pbkdf2" "main" {
  passphrase = "${state_pass}"
}
method "aes_gcm" "main" {
  keys = key_provider.pbkdf2.main
}
state {
  method   = method.aes_gcm.main
  enforced = true
}
plan {
  method   = method.aes_gcm.main
  enforced = true
}
ENC
)"
export TF_ENCRYPTION
unset state_pass

# OpenBao seal key (64 hex characters). Only the openbao Ansible role reads it.
ITEM_OPENBAO_SEAL_KEY="${ITEM_OPENBAO_SEAL_KEY:-infrastructure/openbao-seal-key}"
OPENBAO_SEAL_KEY="$(bw get password "${ITEM_OPENBAO_SEAL_KEY}")" \
  || die "Could not read '${ITEM_OPENBAO_SEAL_KEY}' from Bitwarden."
[[ "${OPENBAO_SEAL_KEY}" =~ ^[0-9a-f]{64}$ ]] \
  || die "The OpenBao seal key must be 64 hex characters (openssl rand -hex 32)."
export OPENBAO_SEAL_KEY

# OpenBao snapshot AppRole. Only the openbao Ansible role reads these.
ITEM_OPENBAO_SNAPSHOT="${ITEM_OPENBAO_APPROLE_SNAPSHOT:-infrastructure/openbao-approle-snapshot}"
OPENBAO_SNAPSHOT_ROLE_ID="$(bw get username "${ITEM_OPENBAO_SNAPSHOT}")" \
  || die "Could not read '${ITEM_OPENBAO_SNAPSHOT}' from Bitwarden. Run: just openbao-snapshot-setup"
OPENBAO_SNAPSHOT_SECRET_ID="$(bw get password "${ITEM_OPENBAO_SNAPSHOT}")" \
  || die "Could not read '${ITEM_OPENBAO_SNAPSHOT}' from Bitwarden."
export OPENBAO_SNAPSHOT_ROLE_ID OPENBAO_SNAPSHOT_SECRET_ID

# OpenBao AppRole for Ansible itself, used by the community.hashi_vault
# lookup plugin to read application secrets at converge time.
ITEM_OPENBAO_ANSIBLE="${ITEM_OPENBAO_APPROLE_ANSIBLE:-infrastructure/openbao-approle-ansible}"
OPENBAO_ANSIBLE_ROLE_ID="$(bw get username "${ITEM_OPENBAO_ANSIBLE}")" \
  || die "Could not read '${ITEM_OPENBAO_ANSIBLE}' from Bitwarden."
OPENBAO_ANSIBLE_SECRET_ID="$(bw get password "${ITEM_OPENBAO_ANSIBLE}")" \
  || die "Could not read '${ITEM_OPENBAO_ANSIBLE}' from Bitwarden."
export OPENBAO_ANSIBLE_ROLE_ID OPENBAO_ANSIBLE_SECRET_ID

exec "$@"
