# OpenSearch Deployment on Bare VMs

This setup deploys a self-hosted OpenSearch cluster on dedicated VMs using Ansible.

## Architecture

- **NOT using AWS OpenSearch Service** (managed service)
- **Self-hosted** on EC2 instances or bare metal VMs
- Deployed via **Ansible** automation
- Kubernetes services connect via **Endpoints**

## Prerequisites

### 1. Provision VMs for OpenSearch

You need to add OpenSearch nodes to your infrastructure. Two options:

#### Option A: Add to Existing Terraform (Recommended)

Create dedicated EC2 instances for OpenSearch in your Terraform configuration:

```hcl
# In terraform/modules/ec2/main.tf or create new module

resource "aws_instance" "opensearch" {
  count                  = 3  # 3-node cluster
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"  # Adjust based on load
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = [aws_security_group.opensearch.id]
  iam_instance_profile   = var.iam_instance_profile_name
  key_name               = var.key_name

  tags = {
    Name    = "${var.project_name}-opensearch-${count.index + 1}"
    Project = var.project_name
    Role    = "opensearch"
  }
}

resource "aws_security_group" "opensearch" {
  name        = "${var.project_name}-opensearch-sg"
  description = "Security group for OpenSearch cluster"
  vpc_id      = var.vpc_id

  # OpenSearch HTTP API
  ingress {
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # OpenSearch transport (inter-node)
  ingress {
    from_port = 9300
    to_port   = 9300
    protocol  = "tcp"
    self      = true
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

#### Option B: Manual VM Provisioning

If using existing VMs, ensure:
- Ubuntu 22.04 LTS
- At least 4GB RAM per node (8GB+ recommended)
- Ports 9200, 9300 open between cluster nodes
- SSH access configured

### 2. Update Ansible Inventory

The Ansible playbook uses dynamic AWS inventory. OpenSearch nodes should be tagged:

```yaml
# In terraform
tags = {
  Role = "opensearch"
}
```

Or manually create a static inventory group:

```ini
# ansible/inventory/hosts
[opensearch]
opensearch-1 ansible_host=10.0.1.100
opensearch-2 ansible_host=10.0.1.101
opensearch-3 ansible_host=10.0.1.102
```

### 3. Configure Variables

Edit `ansible/roles/opensearch/defaults/main.yml` or create group vars:

```yaml
# ansible/group_vars/opensearch.yml
opensearch_heap_size: "4g"  # 50% of node RAM
opensearch_admin_password: "YourSecurePassword123!"
opensearch_cluster_name: "cso2-opensearch-cluster"
```

## Deployment Steps

### 1. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform apply
```

Note the OpenSearch node IPs from outputs.

### 2. Run Ansible Playbook

```bash
cd ../ansible
ansible-playbook -i inventory/aws_ec2.yml site.yml
```

This will:
- Install Java 11
- Download & install OpenSearch 2.11.1
- Configure cluster settings
- Set up SSL/TLS with demo certificates
- Enable security plugin
- Start OpenSearch service

### 3. Verify OpenSearch Cluster

```bash
# SSH to any OpenSearch node
ssh ubuntu@<opensearch-node-ip>

# Check cluster health
curl -k -u admin:YourSecurePassword123! https://localhost:9200/_cluster/health?pretty
```

Expected response:
```json
{
  "cluster_name" : "cso2-opensearch-cluster",
  "status" : "green",
  "number_of_nodes" : 3,
  "number_of_data_nodes" : 3
}
```

### 4. Update Kubernetes Endpoints

Edit `k8s/base/infrastructure/opensearch/service.yaml` and replace IPs:

```yaml
subsets:
  - addresses:
    - ip: <opensearch-node-1-ip>
    - ip: <opensearch-node-2-ip>
    - ip: <opensearch-node-3-ip>
```

### 5. Deploy to Kubernetes

```bash
cd ../../k8s/overlays/dev
kubectl apply -k .
```

### 6. Test from Kubernetes

```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -k -u admin:YourSecurePassword123! \
  https://opensearch.cso2-dev.svc.cluster.local:9200/_cluster/health?pretty
```

## Configuration

### Cluster Size

For production:
- **3 nodes minimum** (quorum for high availability)
- **Odd number** of nodes (3, 5, 7) to prevent split-brain

For dev/testing:
- **1 node** is acceptable

### Resource Recommendations

| Environment | Instance Type | Heap Size | Storage |
|-------------|---------------|-----------|---------|
| Dev/Test    | t3.medium     | 2g        | 20GB    |
| Production  | t3.large      | 4g        | 100GB+  |
| High Load   | r5.xlarge     | 16g       | 500GB+  |

### Security

**Production Hardening:**

1. **Replace demo certificates** with proper SSL certs
2. **Change default admin password** immediately
3. **Enable audit logging**
4. **Restrict network access** to VPC only
5. **Use AWS Secrets Manager** for credentials

## Troubleshooting

### Service won't start

Check logs:
```bash
journalctl -u opensearch -f
tail -f /var/log/opensearch/cso2-opensearch-cluster.log
```

### Memory issues

Increase heap size (max 32GB):
```yaml
opensearch_heap_size: "8g"
```

### Cluster not forming

Check connectivity between nodes:
```bash
telnet <other-node-ip> 9300
```

## Comparison: Self-Hosted vs AWS Managed

| Feature | Self-Hosted (Current) | AWS OpenSearch Service |
|---------|----------------------|------------------------|
| Cost | EC2 instance cost | Managed service premium (~30% more) |
| Management | Manual (Ansible) | Fully managed by AWS |
| Control | Full control | Limited customization |
| Upgrades | Manual | Automated |
| Backups | Manual snapshots | Automated snapshots |
| Scaling | Manual | Auto-scaling options |
| Company Policy | ✅ Compliant | ❌ Not allowed |

## Next Steps

1. Set up automated backups (S3 snapshots)
2. Configure monitoring (Prometheus + Grafana)
3. Implement index lifecycle management
4. Create index templates for your data
5. Configure Logstash/Fluentd for log ingestion
