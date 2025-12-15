data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

locals {
  common_tags = merge(
    {
      Project = var.project_name
      Managed = "terraform"
    },
    var.tags
  )
}

resource "aws_kms_key" "vault" {
  description             = "${var.project_name} Vault auto-unseal"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  tags = local.common_tags
}

resource "aws_kms_alias" "vault" {
  name          = "alias/${var.kms_key_alias}"
  target_key_id = aws_kms_key.vault.id
}

resource "aws_security_group" "vault" {
  name        = "${var.project_name}-vault-sg"
  description = "Security group for Vault EC2 nodes"
  vpc_id      = var.vpc_id

  # Raft and general intra-cluster comms
  ingress {
    description = "Vault cluster internal communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-vault-sg" })
}

resource "aws_security_group" "vault_lb" {
  name        = "${var.project_name}-vault-lb-sg"
  description = "Security group for Vault internal load balancer"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = toset(length(var.client_cidr_blocks) == 0 ? ["0.0.0.0/0"] : var.client_cidr_blocks)
    content {
      description = "Vault API"
      from_port   = 8200
      to_port     = 8200
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-vault-lb-sg" })
}

resource "aws_security_group_rule" "vault_nodes_from_allowed_sg" {
  for_each                 = toset(var.allowed_security_group_ids)
  type                     = "ingress"
  from_port                = 8200
  to_port                  = 8201
  protocol                 = "tcp"
  security_group_id        = aws_security_group.vault.id
  source_security_group_id = each.value
  description              = "Allow Kubernetes nodes to reach Vault"
}

resource "aws_security_group_rule" "vault_nodes_from_lb" {
  type                     = "ingress"
  from_port                = 8200
  to_port                  = 8201
  protocol                 = "tcp"
  security_group_id        = aws_security_group.vault.id
  source_security_group_id = aws_security_group.vault_lb.id
  description              = "Allow load balancer to reach Vault nodes"
}

resource "aws_lb" "vault" {
  name               = "${var.project_name}-vault"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.vault_lb.id]
  subnets            = var.subnet_ids

  tags = merge(local.common_tags, { Name = "${var.project_name}-vault" })
}

resource "aws_lb_target_group" "vault" {
  name     = "${var.project_name}-vault"
  port     = 8200
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 15
    protocol            = "HTTP"
    matcher             = "200-399"
    timeout             = 5
    path                = "/v1/sys/health?standbyok=true&perfstandbyok=true"
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-vault" })
}

resource "aws_lb_listener" "vault" {
  load_balancer_arn = aws_lb.vault.arn
  port              = 8200
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vault.arn
  }
}

resource "aws_instance" "vault" {
  count         = var.node_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = var.subnet_ids[count.index % length(var.subnet_ids)]

  vpc_security_group_ids = [aws_security_group.vault.id]
  iam_instance_profile   = var.iam_instance_profile
  key_name               = var.key_name

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-vault-${count.index + 1}"
      Role = "vault"
    }
  )
}

resource "aws_lb_target_group_attachment" "vault" {
  count            = var.node_count
  target_group_arn = aws_lb_target_group.vault.arn
  target_id        = aws_instance.vault[count.index].id
  port             = 8200
}
