# CSO2 Kubernetes Manifests

## Quick Start

```bash
# 1. Install the External Secrets Operator (ESO) so Vault values sync into Kubernetes
helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace

# 2. Point the dev overlay at your Vault instance and seed secrets
scripts/local/start_dev_vault.sh                             # optional helper
# Update overlays/dev/vault-external-service.yaml so "vault" resolves to your host/IP
vault secrets enable -path=secret kv-v2                      # run once per Vault
openssl genrsa -out /tmp/jwt-private.pem 4096
openssl rsa -in /tmp/jwt-private.pem -pubout -out /tmp/jwt-public.pem
PRIVATE_KEY=$(awk '{printf "%s\\n", $0}' /tmp/jwt-private.pem | sed 's/\\n$//')
PUBLIC_KEY=$(awk '{printf "%s\\n", $0}' /tmp/jwt-public.pem | sed 's/\\n$//')
vault kv put secret/cso2/dev/user-identity-service \
  DATABASE_PASSWORD=changeme \
  MONGODB_URI="mongodb://admin:changeme@mongodb:27017/cso2_user_identity" \
  JWT_PRIVATE_KEY="$PRIVATE_KEY" \
  JWT_PUBLIC_KEY="$PUBLIC_KEY"
# Repeat vault kv put for redis, postgresql, mongodb, notifications-service, etc.
# The exact keys expected for each secret are listed under overlays/dev/secrets/*.yaml.

# 3. Deploy everything
kubectl apply -k overlays/dev

# 4. Verify
kubectl get all -n cso2-dev

# 5. Test JWKS endpoint (for Istio integration)
kubectl port-forward -n cso2-dev svc/user-identity-service 8081:8081
curl http://localhost:8081/.well-known/jwks.json
```

## Vault (Dev / Minikube)

Vault now runs outside the cluster for every environment. Update `overlays/dev/vault-external-service.yaml` so its `externalName` matches the DNS entry or IP where your dev Vault node (VM, Docker container, etc.) is exposed, then `kubectl apply -k overlays/dev`—the workloads will resolve `vault` to that address. Initialize, unseal, and manage policies directly on that external instance and share the resulting credentials through your usual secure channel rather than `.env` files. For local work run `scripts/local/start_dev_vault.sh` (it launches `hashicorp/vault:1.15.4` on `host.minikube.internal:8201` with persistent storage under `~/.cso2/vault`, falling back to a repo-local `.dev-vault` directory if the default path isn’t writable) or mirror that setup manually so unseal info survives container restarts; inside Kubernetes reference it via `http://vault:8201` by default, and override the listener by exporting `VAULT_PORT` before running the script if needed.

For production/staging the Terraform + Ansible stacks already provision dedicated Vault EC2 nodes behind an internal ALB. Point your Kubernetes workloads at the Route53 name output by `vault_lb_dns_name` instead of deploying Vault inside the cluster.

## Structure

```
k8s/
├── base/
│   ├── infrastructure/     # Shared databases & message queues
│   │   ├── mongodb/
│   │   ├── postgresql/
│   │   ├── redis/
│   │   ├── kafka/
│   │   └── rabbitmq/
│   └── spring-boot/        # Base Spring Boot template (optional reference)
└── overlays/
    └── dev/                # Development environment
        ├── kustomization.yaml
        ├── secrets/        # ExternalSecret + SecretStore definitions (Vault-backed)
        ├── vault-external-service.yaml
        ├── frontend.yaml
        └── ... (services)
```

## Adding a New Service

### Option 1: Copy Existing Service
```bash
cd overlays/dev
cp content-service.yaml new-service.yaml
```

Edit `new-service.yaml`:
```yaml
metadata:
  name: new-service  # Change name
spec:
  template:
    spec:
      containers:
      - image: new-service:latest  # Change image
        ports:
        - containerPort: 8089  # Change port
        env:
        - name: SERVER_PORT
          value: "8089"
        - name: SPRING_DATA_MONGODB_DATABASE
          value: "new_db"  # Service-specific env vars
        envFrom:  # Shared config (leave as-is)
        - configMapRef:
            name: app-config
        - secretRef:
            name: app-secrets
```

Add to `overlays/dev/kustomization.yaml`:
```yaml
resources:
  - new-service.yaml
```

### Option 2: Add to Shared ConfigMap/Secrets

**Common env vars** → `overlays/dev/kustomization.yaml`:
```yaml
configMapGenerator:
  - name: app-config
    literals:
      - NEW_SERVICE_URL=http://new-service:8089
```

**Sensitive data** → add an ExternalSecret under `overlays/dev/secrets/`:
```yaml
# overlays/dev/secrets/new-service-external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: new-service-secrets
  namespace: cso2-dev
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-dev
    kind: SecretStore
  target:
    name: new-service-secrets
  data:
  - secretKey: NEW_SERVICE_API_KEY
    remoteRef:
      key: secret/data/cso2/dev/new-service
      property: NEW_SERVICE_API_KEY
```
Seed Vault with `vault kv put secret/cso2/dev/new-service NEW_SERVICE_API_KEY=secret123` and commit the new YAML file.

## Infrastructure Changes

**Add new database:**
```bash
mkdir -p base/infrastructure/newdb
# Create deployment.yaml, service.yaml, kustomization.yaml inside newdb/
```

Add to `overlays/dev/kustomization.yaml`:
```yaml
resources:
  - ../../base/infrastructure/newdb
```

## Environments

Create new environment:
```bash
cp -r overlays/dev overlays/staging
cd overlays/staging
# Update secrets/ (SecretStore + ExternalSecret manifests), resource limits, replicas
```

Deploy:
```bash
kubectl apply -k overlays/staging
```

## Key Concepts

- **Base** = Reusable infrastructure components
- **Overlay** = Environment-specific configs (dev, staging, prod)
- **ConfigMap** = Non-sensitive shared env vars
- **Secrets** = Sensitive data (passwords, API keys, JWT RSA keys) supplied from Vault via ExternalSecret manifests—never check real values into git
- **envFrom** = Inject all ConfigMap/Secret values into pods

## JWT Configuration (user-identity-service)

The user-identity-service uses **RSA-4096 asymmetric signing** for JWTs to support Istio Gateway validation.

### Key Requirements:
- **Private Key** (`JWT_PRIVATE_KEY`): Used by the service to sign JWTs
- **Public Key** (`JWT_PUBLIC_KEY`): Used by Istio to validate JWTs via JWKS endpoint
- **JWKS Endpoint**: `GET /.well-known/jwks.json` (exposed by user-identity-service)

### Production Deployment:
Production overlays already assume Vault + External Secrets. To update keys:
1. Generate keys using: `openssl genrsa -out jwt-private.pem 4096 && openssl rsa -in jwt-private.pem -pubout -out jwt-public.pem`
2. Write them into Vault at `secret/cso2/prod/user-identity-service` (match the keys shown in `overlays/prod/secrets/user-identity-service-external-secret.yaml`)
3. Ensure the prod SecretStore points at the Route53 name output by `vault_lb_dns_name`
4. Keep PEM content escaped with `\n` when storing as env vars

### JWKS Endpoint Integration:
Configure Istio RequestAuthentication to validate JWTs:
```yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: jwt-auth
spec:
  jwtRules:
  - issuer: "cso2-user-identity-service"
    jwksUri: "http://user-identity-service.cso2-dev.svc.cluster.local:8081/.well-known/jwks.json"
```

## Troubleshooting

```bash
# Preview generated manifests
kubectl kustomize overlays/dev

# Check pod logs
kubectl logs -n cso2-dev deployment/content-service

# Debug secrets
kubectl get secret -n cso2-dev app-secrets -o yaml

# Delete everything
kubectl delete -k overlays/dev
```

## Vault Policy / Role Example

```hcl
path "secret/data/user-identity-service/*" {
  capabilities = ["read"]
}
```

Create the policy and Kubernetes auth role once Vault is running:

```bash
vault policy write user-identity-service user-identity-service-policy.hcl
vault write auth/kubernetes/role/user-identity-service \
  bound_service_account_names=user-identity-service \
  bound_service_account_namespaces=cso2-dev \
  policies=user-identity-service \
  ttl=1h
```

Repeat with service-specific paths listed in `overlays/*/secrets/*.yaml`.
