module "vpc" {
  source             = "./modules/vpc"
  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  public_subnets     = var.public_subnets
  availability_zones = var.availability_zones
}

module "iam" {
  source       = "./modules/iam"
  project_name = var.project_name
}

module "ec2" {
  source                    = "./modules/ec2"
  project_name              = var.project_name
  instance_type             = var.instance_type
  subnet_ids                = module.vpc.public_subnet_ids
  control_plane_sg_id       = module.vpc.control_plane_sg_id
  worker_sg_id              = module.vpc.worker_sg_id
  iam_instance_profile_name = module.iam.iam_instance_profile_name
  key_name                  = var.key_name
  control_plane_count       = 1
  worker_count              = 2
}

module "vault" {
  source                    = "./modules/vault"
  project_name              = var.project_name
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.public_subnet_ids
  instance_type             = var.vault_instance_type
  node_count                = var.vault_node_count
  volume_size               = var.vault_volume_size
  iam_instance_profile      = module.iam.iam_instance_profile_name
  key_name                  = var.key_name
  allowed_security_group_ids = [
    module.vpc.control_plane_sg_id,
    module.vpc.worker_sg_id,
  ]
  client_cidr_blocks = [var.vpc_cidr]
}
