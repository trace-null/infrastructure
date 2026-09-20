# The API token comes from the PROXMOX_VE_API_TOKEN environment variable.
#
# No SSH connection is configured on purpose. It is only needed for snippet
# uploads and a few other operations that this repo does not use.
provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure
}
