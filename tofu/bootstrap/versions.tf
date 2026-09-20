terraform {
  required_version = ">= 1.10.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.113.0"
    }
  }

  # State stays outside the repo. The path is passed at init time by `just init`.
  backend "local" {}

  # State and plan encryption is configured through the TF_ENCRYPTION
  # environment variable (see scripts/with-secrets.sh).
}
