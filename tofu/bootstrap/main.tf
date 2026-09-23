module "openbao" {
  source = "../modules/vm"

  name            = "openbao-1"
  vm_id           = 210
  cores           = 2
  memory_mb       = 2048
  disk_gb         = 20
  ip_address      = local.openbao_ip
  tags            = ["openbao", "opentofu"]
  virtiofs_shares = [{ mapping = "openbao-data" }, { mapping = "openbao-backup" }]
  description     = "OpenBao secrets server. Managed by OpenTofu."

  node_name      = local.vm_defaults.node_name
  datastore_id   = local.vm_defaults.datastore_id
  template_vm_id = local.vm_defaults.template_vm_id
  image_id       = local.vm_defaults.image_id
  bridge         = local.vm_defaults.bridge
  prefix_length  = local.vm_defaults.prefix_length
  gateway        = local.vm_defaults.gateway
  dns_servers    = local.vm_defaults.dns_servers
  username       = local.vm_defaults.username
  ssh_keys       = local.vm_defaults.ssh_keys
}

module "gitlab" {
  source = "../modules/vm"

  name            = "gitlab-1"
  vm_id           = 211
  cores           = 4
  memory_mb       = 8192
  disk_gb         = 40
  ip_address      = local.gitlab_ip
  tags            = ["gitlab", "opentofu"]
  virtiofs_shares = [{ mapping = "gitlab-data" }]
  description     = "GitLab CE. Managed by OpenTofu."

  node_name      = local.vm_defaults.node_name
  datastore_id   = local.vm_defaults.datastore_id
  template_vm_id = local.vm_defaults.template_vm_id
  image_id       = local.vm_defaults.image_id
  bridge         = local.vm_defaults.bridge
  prefix_length  = local.vm_defaults.prefix_length
  gateway        = local.vm_defaults.gateway
  dns_servers    = local.vm_defaults.dns_servers
  username       = local.vm_defaults.username
  ssh_keys       = local.vm_defaults.ssh_keys
}

module "infrastructure_stack" {
  source = "../modules/vm"

  name            = "infrastructure-stack"
  vm_id           = 111
  cores           = 2
  memory_mb       = 4096
  disk_gb         = 30
  ip_address      = local.authentik_ip
  tags            = ["authentik", "openldap", "opentofu"]
  virtiofs_shares = [{ mapping = "authentik-data" }, { mapping = "openldap-data" }]
  description     = "Authentik SSO and OpenLDAP. Managed by OpenTofu."

  node_name      = local.vm_defaults.node_name
  datastore_id   = local.vm_defaults.datastore_id
  template_vm_id = local.vm_defaults.template_vm_id
  image_id       = local.vm_defaults.image_id
  bridge         = local.vm_defaults.bridge
  prefix_length  = local.vm_defaults.prefix_length
  gateway        = local.vm_defaults.gateway
  dns_servers    = local.vm_defaults.dns_servers
  username       = local.vm_defaults.username
  ssh_keys       = local.vm_defaults.ssh_keys
}
