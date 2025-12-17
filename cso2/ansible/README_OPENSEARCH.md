# OpenSearch Deployment with Ansible

This Ansible role deploys a production-ready OpenSearch cluster for centralized logging in the e-commerce platform.

## Overview

- **OpenSearch Version:** 2.11.1
- **OpenSearch Dashboards Version:** 2.11.1
- **Cluster Type:** 3-node cluster (configurable)
- **Purpose:** Centralized logging for all microservices

## Prerequisites

### Control Node (where you run Ansible)
- Ansible 2.10+
- Python 3.8+
- AWS CLI configured (if using dynamic inventory)

### Target Nodes (OpenSearch servers)
- Ubuntu 20.04+ or Debian 11+
- Minimum 4GB RAM (8GB recommended)
- 2+ vCPUs
- 50GB+ disk space
- Java 11 (installed by playbook)
- Open ports: 9200, 9300, 5601

## Quick Start

### 1. Configure Inventory

Edit the inventory file with your server IPs:

```bash
cd Infrastructure/cso2/ansible
vim inventory/opensearch_hosts.yml
```

Update the IP addresses:
```yaml
opensearch:
  hosts:
    opensearch-node-1:
      ansible_host: YOUR_IP_1
    opensearch-node-2:
      ansible_host: YOUR_IP_2
    opensearch-node-3:
      ansible_host: YOUR_IP_3
```

### 2. Configure Variables (Optional)

Customize settings in `vars/opensearch_vars.yml`:

```yaml
opensearch_cluster_name: "ecommerce-logs"
opensearch_heap_size: "2g"  # 50% of available RAM
opensearch_admin_password: "YourSecurePassword!"
opensearch_log_retention_days: 30
```

### 3. Run the Playbook

```bash
# Full deployment
ansible-playbook -i inventory/opensearch_hosts.yml opensearch.yml

# With specific tags
ansible-playbook -i inventory/opensearch_hosts.yml opensearch.yml --tags "install"
ansible-playbook -i inventory/opensearch_hosts.yml opensearch.yml --tags "configure"

# With custom SSH key
ansible-playbook -i inventory/opensearch_hosts.yml opensearch.yml \
  --private-key ~/.ssh/your-key.pem

# Verbose output
ansible-playbook -i inventory/opensearch_hosts.yml opensearch.yml -vvv
```

## Verification Steps

### Method 1: Using the Verification Script

**Linux/macOS:**
```bash
chmod +x scripts/verify_opensearch.sh
./scripts/verify_opensearch.sh <OPENSEARCH_IP> 9200 admin Admin@123!
```

**Windows PowerShell:**
```powershell
.\scripts\verify_opensearch.ps1 -OpenSearchHost "10.0.1.10" -Port 9200
```

### Method 2: Manual Verification Commands

#### Check Cluster Health
```bash
curl -k -u admin:Admin@123! https://<OPENSEARCH_IP>:9200/_cluster/health?pretty
```

Expected output:
```json
{
  "cluster_name" : "ecommerce-logs",
  "status" : "green",
  "number_of_nodes" : 3,
  "number_of_data_nodes" : 3,
  "active_primary_shards" : 1,
  "active_shards" : 2,
  ...
}
```

#### Check Node Status
```bash
curl -k -u admin:Admin@123! https://<OPENSEARCH_IP>:9200/_cat/nodes?v
```

Expected output:
```
ip         heap.percent ram.percent cpu load_1m node.name
10.0.1.10            45          65   5    0.15 opensearch-node-1
10.0.1.11            42          62   3    0.10 opensearch-node-2
10.0.1.12            40          60   2    0.08 opensearch-node-3
```

#### List Indices
```bash
curl -k -u admin:Admin@123! https://<OPENSEARCH_IP>:9200/_cat/indices?v
```

#### Check Index Templates
```bash
curl -k -u admin:Admin@123! https://<OPENSEARCH_IP>:9200/_index_template?pretty
```

#### Test Write Operation
```bash
# Create a test document
curl -k -u admin:Admin@123! -X POST \
  "https://<OPENSEARCH_IP>:9200/test-index/_doc" \
  -H 'Content-Type: application/json' \
  -d '{"message": "Hello OpenSearch!", "timestamp": "2025-12-17T10:00:00Z"}'

# Verify the document
curl -k -u admin:Admin@123! "https://<OPENSEARCH_IP>:9200/test-index/_search?pretty"

# Delete test index
curl -k -u admin:Admin@123! -X DELETE "https://<OPENSEARCH_IP>:9200/test-index"
```

#### Access OpenSearch Dashboards
Open in browser: `http://<OPENSEARCH_IP>:5601`

**Login Credentials:**
- Username: `admin`
- Password: `Admin@123!` (or your configured password)

### Method 3: Service Status Verification

SSH into the OpenSearch nodes and run:

```bash
# Check OpenSearch service status
sudo systemctl status opensearch

# Check OpenSearch Dashboards status (on first node)
sudo systemctl status opensearch-dashboards

# View OpenSearch logs
sudo journalctl -u opensearch -f

# Check listening ports
sudo netstat -tlnp | grep -E '9200|9300|5601'
```

## Verification Checklist

| Check | Command | Expected Result |
|-------|---------|-----------------|
| Service Running | `systemctl status opensearch` | Active (running) |
| Cluster Health | `curl /_cluster/health` | status: green/yellow |
| All Nodes Up | `curl /_cat/nodes` | 3 nodes listed |
| Write Test | POST a document | {"result": "created"} |
| Dashboards | Open :5601 in browser | Login page visible |
| Security | `curl /_plugins/_security/api/account` | user_name: admin |

## Troubleshooting

### Common Issues

**1. Cluster not forming (yellow/red status)**
```bash
# Check discovery
curl -k -u admin:Admin@123! https://<IP>:9200/_cluster/state/nodes?pretty

# Verify network connectivity between nodes
ping <other-node-ip>
telnet <other-node-ip> 9300
```

**2. Out of Memory**
```bash
# Check JVM heap
curl -k -u admin:Admin@123! https://<IP>:9200/_nodes/stats/jvm?pretty

# Reduce heap size in vars/opensearch_vars.yml
opensearch_heap_size: "1g"
```

**3. Certificate Issues**
```bash
# Regenerate certificates
cd /opt/opensearch/plugins/opensearch-security/tools/
./install_demo_configuration.sh -y -i -s
```

**4. Permission Denied**
```bash
# Fix ownership
sudo chown -R opensearch:opensearch /opt/opensearch
sudo chown -R opensearch:opensearch /var/lib/opensearch
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    OpenSearch Cluster                        │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   Node 1     │  │   Node 2     │  │   Node 3     │       │
│  │   Master     │  │   Master     │  │   Master     │       │
│  │   Data       │  │   Data       │  │   Data       │       │
│  │   Ingest     │  │   Ingest     │  │   Ingest     │       │
│  │   :9200      │  │   :9200      │  │   :9200      │       │
│  │   :9300      │  │   :9300      │  │   :9300      │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│         │                 │                 │                │
│         └─────────────────┼─────────────────┘                │
│                           │                                  │
│  ┌────────────────────────▼────────────────────────────┐    │
│  │           OpenSearch Dashboards (:5601)              │    │
│  │           (Installed on Node 1)                      │    │
│  └──────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              │                           │
    ┌─────────▼─────────┐     ┌──────────▼──────────┐
    │   Fluent Bit      │     │   Application       │
    │   (Log Shipper)   │     │   Direct Logging    │
    └───────────────────┘     └─────────────────────┘
```

## Directory Structure

```
ansible/
├── ansible.cfg                     # Ansible configuration
├── site.yml                        # Main playbook
├── opensearch.yml                  # OpenSearch deployment playbook
├── inventory/
│   ├── aws_ec2.yml                # AWS dynamic inventory
│   └── opensearch_hosts.yml       # Static OpenSearch inventory
├── vars/
│   └── opensearch_vars.yml        # OpenSearch variables
├── roles/
│   └── opensearch/
│       ├── defaults/main.yml      # Default variables
│       ├── tasks/
│       │   ├── main.yml           # Main tasks
│       │   ├── install.yml        # Installation tasks
│       │   ├── configure.yml      # Configuration tasks
│       │   ├── security.yml       # Security setup
│       │   ├── dashboards.yml     # Dashboards setup
│       │   └── index_templates.yml # Index templates
│       ├── templates/
│       │   ├── opensearch.yml.j2
│       │   ├── jvm.options.j2
│       │   ├── opensearch.service.j2
│       │   ├── opensearch_dashboards.yml.j2
│       │   ├── opensearch-dashboards.service.j2
│       │   ├── internal_users.yml.j2
│       │   └── roles_mapping.yml.j2
│       └── handlers/main.yml      # Service handlers
└── scripts/
    ├── verify_opensearch.sh       # Linux verification script
    └── verify_opensearch.ps1      # Windows verification script
```

## Security Notes

1. **Change default password** before production deployment
2. **Use Ansible Vault** for sensitive data:
   ```bash
   ansible-vault encrypt_string 'YourSecurePassword!' --name 'opensearch_admin_password'
   ```
3. **Enable TLS** for production (demo certs are insecure)
4. **Configure firewall** to restrict access to OpenSearch ports

## Integration with Kubernetes

For log shipping from Kubernetes pods, deploy Fluent Bit:

```yaml
# fluent-bit-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
data:
  output-opensearch.conf: |
    [OUTPUT]
        Name            opensearch
        Match           *
        Host            opensearch-node-1.example.com
        Port            9200
        HTTP_User       logstash
        HTTP_Passwd     YourPassword
        Index           ecommerce-logs
        tls             On
        tls.verify      Off
```

## Maintenance Commands

```bash
# Check cluster health
curl -k -u admin:Admin@123! https://<IP>:9200/_cluster/health?pretty

# View shard allocation
curl -k -u admin:Admin@123! https://<IP>:9200/_cat/shards?v

# Check disk usage
curl -k -u admin:Admin@123! https://<IP>:9200/_cat/allocation?v

# Force shard reallocation
curl -k -u admin:Admin@123! -X POST https://<IP>:9200/_cluster/reroute?retry_failed=true
```

## References

- [OpenSearch Documentation](https://opensearch.org/docs/latest/)
- [OpenSearch Dashboards](https://opensearch.org/docs/latest/dashboards/)
- [Ansible Documentation](https://docs.ansible.com/)
