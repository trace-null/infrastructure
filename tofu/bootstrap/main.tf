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
  virtiofs_shares = [{ mapping = "openbao-data" }]
  description     = "OpenBao secrets server. Managed by OpenTofu."
}
