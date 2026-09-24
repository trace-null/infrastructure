output "openbao_ip" {
  value = local.openbao_ip
}

output "openbao_vm_id" {
  value = module.openbao.vm_id
}

output "gitlab_ip" {
  value = local.gitlab_ip
}

output "gitlab_vm_id" {
  value = module.gitlab.vm_id
}

output "gitlab_runner_ip" {
  value = local.gitlab_runner_ip
}

output "gitlab_runner_vm_id" {
  value = module.gitlab_runner.vm_id
}

output "authentik_ip" {
  value = local.authentik_ip
}

output "authentik_vm_id" {
  value = module.infrastructure_stack.vm_id
}
