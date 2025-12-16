output "s3_bucket_name" {
  description = "S3 bucket for Terraform state"
  value       = module.backend.s3_bucket_name
}

output "dynamodb_table_name" {
  description = "DynamoDB table for Terraform state locking"
  value       = module.backend.dynamodb_table_name
}

output "control_plane_public_ips" {
  value = module.ec2.control_plane_public_ips
}

output "control_plane_private_ips" {
  value = module.ec2.control_plane_private_ips
}

output "worker_public_ips" {
  value = module.ec2.worker_public_ips
}
