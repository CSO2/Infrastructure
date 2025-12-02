# CSO2 Kubernetes Manifests

## Quick Start

```bash
# 1. Copy secrets template
cd overlays/dev
cp .env.example .env

# 2. Generate JWT RSA keys (required for user-identity-service)
openssl genrsa -out /tmp/jwt-private.pem 4096
openssl rsa -in /tmp/jwt-private.pem -pubout -out /tmp/jwt-public.pem

# 3. Update .env with JWT keys (replace newlines with \n)
PRIVATE_KEY=$(cat /tmp/jwt-private.pem | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
PUBLIC_KEY=$(cat /tmp/jwt-public.pem | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
# Then manually edit .env or use sed to replace JWT_PRIVATE_KEY and JWT_PUBLIC_KEY

# 4. Deploy everything
kubectl apply -k overlays/dev

# 5. Verify
kubectl get all -n cso2-dev

# 6. Test JWKS endpoint (for Istio integration)
kubectl port-forward -n cso2-dev svc/user-identity-service 8081:8081
curl http://localhost:8081/.well-known/jwks.json
```

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
        ├── .env            # ❌ gitignored - actual secrets
        ├── .env.example    # ✅ committed - template
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

**Sensitive data** → `overlays/dev/secrets.env`:
```
NEW_SERVICE_API_KEY=secret123
```

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
# Update secrets.env, resource limits, replicas
```

Deploy:
```bash
kubectl apply -k overlays/staging
```

## Key Concepts

- **Base** = Reusable infrastructure components
- **Overlay** = Environment-specific configs (dev, staging, prod)
- **ConfigMap** = Non-sensitive shared env vars
- **Secrets** = Sensitive data (passwords, API keys, JWT RSA keys) - NEVER commit `.env`
- **envFrom** = Inject all ConfigMap/Secret values into pods

## JWT Configuration (user-identity-service)

The user-identity-service uses **RSA-4096 asymmetric signing** for JWTs to support Istio Gateway validation.

### Key Requirements:
- **Private Key** (`JWT_PRIVATE_KEY`): Used by the service to sign JWTs
- **Public Key** (`JWT_PUBLIC_KEY`): Used by Istio to validate JWTs via JWKS endpoint
- **JWKS Endpoint**: `GET /.well-known/jwks.json` (exposed by user-identity-service)

### Production Deployment:
For production environments, **DO NOT** hardcode keys in `.env` files. Instead:
1. Generate keys using: `openssl genrsa -out jwt-private.pem 4096 && openssl rsa -in jwt-private.pem -pubout -out jwt-public.pem`
2. Store keys in your secret manager (AWS Secrets Manager, GCP Secret Manager, HashiCorp Vault, etc.)
3. Configure Kubernetes to inject secrets via External Secrets Operator or native CSI drivers
4. Ensure keys are formatted in PEM with `\n` literals (not actual newlines) for env vars

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
