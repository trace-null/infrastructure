#!/usr/bin/env bash
# scripts/set-image.sh <release-date>
#
# Pins the Ubuntu 26.04 cloud image release and its SHA-256 for OpenTofu.
# Example: scripts/set-image.sh 20260918
#
# Releases are listed at https://cloud-images.ubuntu.com/releases/resolute/

set -euo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

release="${1:-}"
[[ "${release}" =~ ^[0-9]{8}$ ]] || die "Usage: $0 <release-date>, for example 20260918"

file="ubuntu-26.04-server-cloudimg-amd64.img"
base="https://cloud-images.ubuntu.com/releases/resolute/release-${release}"

sums="$(curl -fsSL "${base}/SHA256SUMS")" || die "Could not download ${base}/SHA256SUMS"
sum="$(printf '%s\n' "${sums}" | awk -v f="${file}" '$2==f || $2=="*"f {print $1; exit}')"
[[ "${sum}" =~ ^[0-9a-f]{64}$ ]] || die "No checksum for ${file} in release ${release}."

out="$(cd "$(dirname "$0")/.." && pwd)/tofu/bootstrap/image.auto.tfvars.json"
printf '{\n  "ubuntu_image_release": "%s",\n  "ubuntu_image_sha256": "%s"\n}\n' "${release}" "${sum}" > "${out}"

echo "Pinned release ${release}"
echo "SHA-256 ${sum}"
echo "Written to ${out}"
