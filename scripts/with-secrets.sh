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
ITEM_PROXMOX_TOKEN="${ITEM_PROXMOX_TOKEN:-infra/proxmox-api-token}"
ITEM_STATE_PASSPHRASE="${ITEM_STATE_PASSPHRASE:-infra/tofu-state-passphrase}"

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

# Later: log in to OpenBao here and export VAULT_ADDR and VAULT_TOKEN.

exec "$@"
