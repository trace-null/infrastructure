# shellcheck shell=bash
# Shared helpers for the OpenBao scripts. Sourced, not run.

die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

need_tools() {
  local tool
  for tool in "$@"; do
    command -v "${tool}" >/dev/null 2>&1 || die "${tool} is not installed"
  done
  [[ -n "${BW_SESSION:-}" ]] || die 'Bitwarden is locked. Run: export BW_SESSION="$(bw unlock --raw)"'
}

# Number of Bitwarden items with exactly this name.
bw_count() {
  bw list items --search "$1" | jq --arg n "$1" '[.[] | select(.name == $n)] | length'
}

# bw_create <name> <login|note> <notes> [password] [username]
bw_create() {
  bw get template item | jq --arg n "$1" --arg kind "$2" --arg notes "$3" \
      --arg pw "${4:-}" --arg user "${5:-}" '
    .name = $n
    | .notes = $notes
    | if $kind == "note"
      then .type = 2 | .secureNote = {type: 0} | .login = null
      else .type = 1 | .login = {
             uris: [],
             username: (if $user == "" then null else $user end),
             password: $pw,
             totp: null
           }
      end' \
    | bw encode | bw create item > /dev/null
}

bw_delete() {
  local id
  id="$(bw get item "$1" | jq -r .id)"
  bw delete item "${id}" --permanent > /dev/null
}

# Sets BAO_ADDR and BAO_CACERT for the bao CLI.
openbao_env() {
  local host
  if [[ -z "${BAO_ADDR:-}" ]]; then
    host="$(ansible-inventory -i "${repo_root}/ansible/inventory" --host openbao-1 2>/dev/null \
      | jq -r '.ansible_host // empty')" || true
    [[ -n "${host}" ]] || die "Could not read the OpenBao address from the inventory. Set BAO_ADDR."
    export BAO_ADDR="https://${host}:8200"
  else
    host="${BAO_ADDR#*://}"; host="${host%%:*}"
  fi

  export BAO_CACERT="${BAO_CACERT:-${HOME}/.config/infra/openbao.crt}"
  if [[ ! -f "${BAO_CACERT}" ]]; then
    info "No certificate at ${BAO_CACERT}. Fetching it over SSH from ${host}"
    mkdir -p "$(dirname "${BAO_CACERT}")"
    ssh -o BatchMode=yes "ansible@${host}" 'cat /mnt/infra/tls/openbao.crt' > "${BAO_CACERT}.tmp" \
      || { rm -f "${BAO_CACERT}.tmp"; die "Could not fetch the certificate. Run the bootstrap playbook from this machine, or copy it to ${BAO_CACERT}."; }
    openssl x509 -in "${BAO_CACERT}.tmp" -noout 2>/dev/null \
      || { rm -f "${BAO_CACERT}.tmp"; die "The fetched file is not a certificate."; }
    mv "${BAO_CACERT}.tmp" "${BAO_CACERT}"
  fi
}
