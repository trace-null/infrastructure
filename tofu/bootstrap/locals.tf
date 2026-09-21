locals {
  # The inventory is the single source of truth for addresses and the login user.
  inventory  = yamldecode(file("${path.module}/../../ansible/inventory/hosts.yml"))
  group_vars = yamldecode(file("${path.module}/../../ansible/inventory/group_vars/all.yml"))

  openbao_ip   = local.inventory.all.children.openbao_hosts.hosts["openbao-1"].ansible_host
  gitlab_ip    = local.inventory.all.children.gitlab_hosts.hosts["gitlab-1"].ansible_host
  ansible_user = local.group_vars.ansible_user

  # Public keys allowed to log in as the Ansible user. One per line in authorized_keys.
  ssh_keys = [
    for line in split("\n", file("${path.module}/authorized_keys")) : trimspace(line)
    if trimspace(line) != "" && !startswith(trimspace(line), "#")
  ]
}
