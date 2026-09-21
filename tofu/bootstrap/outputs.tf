output "openbao_ip" {
  value = local.openbao_ip
}

output "openbao_vm_id" {
  value = module.openbao.vm_id
}

output "gitlab_ip" {
  value = local.gitlab_ip
}
