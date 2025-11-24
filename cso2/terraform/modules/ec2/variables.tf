variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "control_plane_sg_id" {
  description = "Security Group ID for Control Plane"
  type        = string
}

variable "worker_sg_id" {
  description = "Security Group ID for Workers"
  type        = string
}

variable "iam_instance_profile_name" {
  description = "IAM Instance Profile Name"
  type        = string
}

variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "key_name" {
  description = "SSH Key Name"
  type        = string
  default     = null
}
