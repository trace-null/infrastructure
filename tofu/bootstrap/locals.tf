locals {
  # The inventory is the single source of truth for addresses and the login user.
  inventory  = yamldecode(file("${path.module}/../../ansible/inventory/hosts.yml"))
  group_vars = yamldecode(file("${path.module}/../../ansible/inventory/group_vars/all.yml"))

  openbao_ip   = local.inventory.all.children.openbao_hosts.hosts["openbao-1"].ansible_host
  gitlab_ip    = local.inventory.all.children.gitlab_hosts.hosts["gitlab-1"].ansible_host
  authentik_ip = local.inventory.all.children.authentik_hosts.hosts["infrastructure-stack"].ansible_host
  ansible_user = local.group_vars.ansible_user

  # Public keys allowed to log in as the Ansible user. One per line in authorized_keys.
  ssh_keys = [
    for line in split("\n", file("${path.module}/authorized_keys")) : trimspace(line)
    if trimspace(line) != "" && !startswith(trimspace(line), "#")
  ]
}

locals {
  # Values every VM shares. Per-VM blocks in main.tf merge these in and
  # only specify what's actually different for that VM.
  vm_defaults = {
    node_name      = var.node_name
    datastore_id   = var.vm_datastore_id
    template_vm_id = local.template_vm_id
    image_id       = local.image_id
    bridge         = var.network_bridge
    prefix_length  = var.network_prefix_length
    gateway        = var.network_gateway
    dns_servers    = var.dns_servers
    username       = local.ansible_user
    ssh_keys       = local.ssh_keys
  }
}
