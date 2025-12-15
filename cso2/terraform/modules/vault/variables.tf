variable "project_name" {
  description = "Project name for tagging."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where Vault runs."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets that host Vault instances and load balancer."
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type for Vault nodes."
  type        = string
  default     = "t3.small"
}

variable "node_count" {
  description = "Number of Vault instances (minimum 3 for HA)."
  type        = number
  default     = 3
}

variable "volume_size" {
  description = "Root volume size in GiB for Vault instances."
  type        = number
  default     = 40
}

variable "iam_instance_profile" {
  description = "Instance profile attached to Vault nodes (SSM access, etc.)."
  type        = string
  default     = null
}

variable "key_name" {
  description = "SSH key pair name."
  type        = string
  default     = null
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to reach Vault nodes directly."
  type        = list(string)
  default     = []
}

variable "client_cidr_blocks" {
  description = "CIDR blocks allowed to reach the Vault load balancer."
  type        = list(string)
  default     = []
}

variable "kms_key_deletion_window" {
  description = "Days before scheduled deletion of the Vault KMS key."
  type        = number
  default     = 7
}

variable "kms_key_alias" {
  description = "Alias for the Vault unseal KMS key."
  type        = string
  default     = "vault-auto-unseal"
}

variable "tags" {
  description = "Additional tags to apply to Vault resources."
  type        = map(string)
  default     = {}
}
