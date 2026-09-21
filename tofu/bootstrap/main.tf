module "openbao" {
  source = "../modules/vm"

  name            = "openbao-1"
  vm_id           = 210
  node_name       = var.node_name
  datastore_id    = var.vm_datastore_id
  template_vm_id  = local.template_vm_id
  image_id        = local.image_id
  bridge          = var.network_bridge
  cores           = 2
  memory_mb       = 2048
  disk_gb         = 20
  ip_address      = local.openbao_ip
  prefix_length   = var.network_prefix_length
  gateway         = var.network_gateway
  dns_servers     = var.dns_servers
  username        = local.ansible_user
  ssh_keys        = local.ssh_keys
  tags            = ["openbao", "opentofu"]
  virtiofs_shares = [{ mapping = "openbao-data" }, { mapping = "openbao-backup" }]
  description     = "OpenBao secrets server. Managed by OpenTofu."
}

module "gitlab" {
  source = "../modules/vm"

  name            = "gitlab-1"
  vm_id           = 211
  node_name       = var.node_name
  datastore_id    = var.vm_datastore_id
  template_vm_id  = local.template_vm_id
  image_id        = local.image_id
  bridge          = var.network_bridge
  cores           = 4
  memory_mb       = 8192
  disk_gb         = 40
  ip_address      = local.gitlab_ip
  prefix_length   = var.network_prefix_length
  gateway         = var.network_gateway
  dns_servers     = var.dns_servers
  username        = local.ansible_user
  ssh_keys        = local.ssh_keys
  tags            = ["gitlab", "opentofu"]
  virtiofs_shares = [{ mapping = "gitlab-data" }]
  description     = "GitLab CE. Managed by OpenTofu."
}

module "infrastructure_stack" {
  source = "../modules/vm"

  name            = "infrastructure-stack"
  vm_id           = 111
  node_name       = var.node_name
  datastore_id    = var.vm_datastore_id
  template_vm_id  = local.template_vm_id
  image_id        = local.image_id
  bridge          = var.network_bridge
  cores           = 2
  memory_mb       = 4096
  disk_gb         = 30
  ip_address      = local.authentik_ip
  prefix_length   = var.network_prefix_length
  gateway         = var.network_gateway
  dns_servers     = var.dns_servers
  username        = local.ansible_user
  ssh_keys        = local.ssh_keys
  tags            = ["authentik", "opentofu"]
  virtiofs_shares = [{ mapping = "authentik-data" }]
  description     = "Authentik SSO. Managed by OpenTofu."
}
