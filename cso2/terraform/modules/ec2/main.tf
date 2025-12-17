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

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "control_plane" {
  count                  = var.control_plane_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = [var.control_plane_sg_id]
  iam_instance_profile   = var.iam_instance_profile_name
  key_name               = var.key_name

  tags = {
    Name           = "${var.project_name}-control-plane-${count.index + 1}"
    Project        = var.project_name
    Role           = "control-plane"
    OpensearchNode = "true"
  }
}

resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = [var.worker_sg_id]
  iam_instance_profile   = var.iam_instance_profile_name
  key_name               = var.key_name

  tags = {
    Name = "${var.project_name}-worker-${count.index + 1}"
    Project = var.project_name
    Role = "worker"
  }
}

# Elastic IP for Control Plane - Makes the public IP permanent
# This ensures DNS records pointing to this IP remain valid after instance restarts
resource "aws_eip" "control_plane" {
  count  = var.control_plane_count
  domain = "vpc"

  tags = {
    Name    = "${var.project_name}-control-plane-eip-${count.index + 1}"
    Project = var.project_name
    Role    = "control-plane"
  }
}

# Associate Elastic IP with Control Plane instance
resource "aws_eip_association" "control_plane" {
  count         = var.control_plane_count
  instance_id   = aws_instance.control_plane[count.index].id
  allocation_id = aws_eip.control_plane[count.index].id
}
