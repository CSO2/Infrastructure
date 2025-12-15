output "control_plane_public_ips" {
  value = module.ec2.control_plane_public_ips
}

output "worker_public_ips" {
  value = module.ec2.worker_public_ips
}

output "vault_lb_dns_name" {
  value       = module.vault.load_balancer_dns
  description = "Internal DNS name for the Vault load balancer."
}

output "vault_kms_key_arn" {
  value       = module.vault.kms_key_arn
  description = "KMS key ARN used for Vault auto-unseal."
}

output "vault_security_group_id" {
  value       = module.vault.security_group_id
  description = "Security group protecting Vault instances."
}
