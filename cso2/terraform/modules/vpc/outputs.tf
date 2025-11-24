output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "control_plane_sg_id" {
  value = aws_security_group.k8s_control_plane.id
}

output "worker_sg_id" {
  value = aws_security_group.k8s_worker.id
}
