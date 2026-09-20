#!/usr/bin/env bash
# scripts/setup-wsl.sh
#
# Installs the client tooling needed to work with this repo from WSL
# (Debian or Ubuntu). Safe to run more than once.
#
# Installs: git, jq, Ansible (with hvac and the hashi_vault collection),
# OpenTofu, just, the OpenBao client (bao) and the Bitwarden CLI (bw).
#
# sudo is used for apt and for the OpenTofu installer. Everything else
# goes into ~/.local/bin without elevated rights.
#
# Optional overrides (environment variables):
#   OPENBAO_VERSION   pin a release, for example 2.1.0 (default: latest)
#   ALLOW_UNVERIFIED  set to 1 to carry on if no checksum file is found

set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OPENBAO_VERSION="${OPENBAO_VERSION:-latest}"
ALLOW_UNVERIFIED="${ALLOW_UNVERIFIED:-0}"
ARCH=""
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

preflight() {
  log "Checking environment"

  [[ "${EUID}" -ne 0 ]] || die "Run this as your normal user and not as root."
  have apt-get || die "This script supports Debian and Ubuntu (apt) only."

  if ! grep -qi microsoft /proc/version 2>/dev/null; then
    warn "This does not look like WSL. Carrying on anyway."
  fi

  case "${REPO_ROOT}" in
    /mnt/*)
      warn "The repo is on a Windows mount (${REPO_ROOT})."
      warn "Move it into the Linux filesystem, for example ~/infra, to avoid Ansible and SSH permission problems."
      ;;
  esac

  case "$(uname -m)" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *)       die "Unsupported architecture: $(uname -m)" ;;
  esac

  mkdir -p "${BIN_DIR}"
  export PATH="${BIN_DIR}:${PATH}"
}

install_apt_packages() {
  log "Installing base packages"
  sudo apt-get update -y
  sudo apt-get install -y git jq curl unzip ca-certificates gnupg python3 python3-venv pipx
}

install_ansible() {
  log "Installing Ansible"
  pipx ensurepath >/dev/null 2>&1 || true

  if pipx list --short 2>/dev/null | grep -q '^ansible '; then
    pipx upgrade ansible || true
  else
    pipx install --include-deps ansible
  fi

  # hvac must live in the same environment as Ansible so the
  # community.hashi_vault plugins can talk to OpenBao.
  pipx inject ansible hvac

  log "Installing Ansible collections"
  local reqs="${REPO_ROOT}/ansible/requirements.yml"
  if [[ -f "${reqs}" ]]; then
    ansible-galaxy collection install -r "${reqs}"
  fi
  ansible-galaxy collection install community.hashi_vault
}

install_opentofu() {
  if have tofu; then
    log "OpenTofu already installed ($(tofu version | head -n1))"
    return
  fi

  log "Installing OpenTofu"
  curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh \
    -o "${TMP_DIR}/install-opentofu.sh"
  chmod +x "${TMP_DIR}/install-opentofu.sh"
  sudo "${TMP_DIR}/install-opentofu.sh" --install-method deb
}

install_just() {
  if have just; then
    log "just already installed ($(just --version))"
    return
  fi

  log "Installing just"
  if apt-cache show just >/dev/null 2>&1; then
    sudo apt-get install -y just
  else
    curl --proto '=https' --tlsv1.2 -fsSL https://just.systems/install.sh \
      -o "${TMP_DIR}/just-install.sh"
    bash "${TMP_DIR}/just-install.sh" --to "${BIN_DIR}"
  fi
}

install_openbao() {
  if have bao; then
    if [[ "${OPENBAO_VERSION}" == "latest" ]] || bao version 2>/dev/null | grep -q "${OPENBAO_VERSION}"; then
      log "OpenBao client already installed ($(bao version 2>/dev/null | head -n1))"
      return
    fi
  fi

  local version="${OPENBAO_VERSION}"
  if [[ "${version}" == "latest" ]]; then
    # Read the newest stable tag from git so the GitHub API rate limit is not an issue.
    version="$(git ls-remote --tags --refs https://github.com/openbao/openbao.git \
      | awk '{print $2}' | sed 's#refs/tags/v##' \
      | grep -E '^[0-9]+[.][0-9]+[.][0-9]+$' | sort -V | tail -n 1)"
  fi
  [[ -n "${version}" ]] || die "Could not work out which OpenBao version to install."

  log "Installing OpenBao client (${version})"

  local base="https://github.com/openbao/openbao/releases/download/v${version}"
  local name="openbao_${version}_linux_${ARCH}.tar.gz"
  local archive="${TMP_DIR}/${name}"

  curl -fsSL "${base}/${name}" -o "${archive}" \
    || die "Could not download ${name}. Check the version number."

  if curl -fsSL "${base}/checksums.txt" -o "${TMP_DIR}/sums.txt"; then
    local expected actual
    expected="$(awk -v f="${name}" '$2==f || $2=="*"f {print $1; exit}' "${TMP_DIR}/sums.txt")"
    [[ -n "${expected}" ]] || die "No checksum entry found for ${name}."
    actual="$(sha256sum "${archive}" | awk '{print $1}')"
    [[ "${expected}" == "${actual}" ]] || die "Checksum mismatch for the OpenBao download."
    echo "Checksum verified."
  elif [[ "${ALLOW_UNVERIFIED}" == "1" ]]; then
    warn "No checksum file found. Installing without verification."
  else
    die "No checksum file found. Set ALLOW_UNVERIFIED=1 to override."
  fi

  mkdir -p "${TMP_DIR}/bao-extract"
  tar -xzf "${archive}" -C "${TMP_DIR}/bao-extract"
  local bin
  bin="$(find "${TMP_DIR}/bao-extract" -type f -name bao | head -n1)"
  [[ -n "${bin}" ]] || die "The bao binary was not found in the archive."
  install -m 0755 "${bin}" "${BIN_DIR}/bao"
}

install_bitwarden_cli() {
  if have bw; then
    log "Bitwarden CLI already installed ($(bw --version))"
    return
  fi

  if [[ "$(uname -m)" != "x86_64" ]]; then
    warn "The Bitwarden CLI binary is x86_64 only. Install it with npm instead."
    return
  fi

  log "Installing Bitwarden CLI"
  curl -fsSL "https://vault.bitwarden.com/download/?app=cli&platform=linux" \
    -o "${TMP_DIR}/bw.zip"
  mkdir -p "${TMP_DIR}/bw"
  unzip -o -q "${TMP_DIR}/bw.zip" -d "${TMP_DIR}/bw"
  install -m 0755 "${TMP_DIR}/bw/bw" "${BIN_DIR}/bw"
}

verify() {
  log "Verifying installation"
  local missing=0 tool
  for tool in git jq tofu ansible ansible-playbook ansible-galaxy just bao bw; do
    if have "${tool}"; then
      printf '  %-18s ok\n' "${tool}"
    else
      printf '  %-18s MISSING\n' "${tool}"
      missing=1
    fi
  done

  if pipx runpip ansible show hvac >/dev/null 2>&1; then
    printf '  %-18s ok\n' "hvac"
  else
    printf '  %-18s MISSING\n' "hvac"
    missing=1
  fi

  echo
  have ansible && ansible --version | head -n1
  have tofu    && tofu version | head -n1
  have bao     && bao version
  have bw      && echo "bw $(bw --version)"

  [[ "${missing}" -eq 0 ]] || die "Some tools are missing. See the output above."
}

main() {
  preflight
  install_apt_packages
  install_ansible
  install_opentofu
  install_just
  install_openbao
  install_bitwarden_cli
  verify

  log "Done"
  echo "Open a new shell (or run: source ~/.bashrc) so PATH changes take effect."
}

main "$@"
