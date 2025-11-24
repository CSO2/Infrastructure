output "control_plane_public_ips" {
  value = module.ec2.control_plane_public_ips
}

output "worker_public_ips" {
  value = module.ec2.worker_public_ips
}
