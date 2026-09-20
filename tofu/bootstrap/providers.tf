# The API token comes from the PROXMOX_VE_API_TOKEN environment variable.
provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure

  # Some operations (snippets, cloud-init files) need SSH to the Proxmox node
  # as well as the API. The key is taken from your ssh-agent.
  ssh {
    agent    = true
    username = var.proxmox_ssh_user
  }
}
