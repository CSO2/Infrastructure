output "kms_key_arn" {
  value       = aws_kms_key.vault.arn
  description = "KMS key ARN used for auto-unseal."
}

output "security_group_id" {
  value       = aws_security_group.vault.id
  description = "Security group protecting Vault instances."
}

output "load_balancer_dns" {
  value       = aws_lb.vault.dns_name
  description = "Internal ALB DNS name used by Kubernetes clusters."
}

output "instance_ids" {
  value       = aws_instance.vault[*].id
  description = "Vault EC2 instance IDs."
}
