output "control_plane_public_ips" {
  value = aws_instance.control_plane[*].public_ip
}

output "worker_public_ips" {
  value = aws_instance.worker[*].public_ip
}

output "control_plane_private_ips" {
  value = aws_instance.control_plane[*].private_ip
}

output "worker_private_ips" {
  value = aws_instance.worker[*].private_ip
}

# Elastic IP addresses for control plane (permanent public IPs)
output "control_plane_elastic_ips" {
  description = "Elastic IP addresses for control plane instances - these are permanent"
  value       = aws_eip.control_plane[*].public_ip
}
