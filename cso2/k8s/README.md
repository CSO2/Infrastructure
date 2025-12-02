# CSO2 Kubernetes Manifests

## Quick Start

```bash
# 1. Copy secrets template
cd overlays/dev
cp secrets.env.example secrets.env

# 2. Edit secrets.env with actual values
vim secrets.env

# 3. Deploy everything
kubectl apply -k overlays/dev

# 4. Verify
kubectl get all -n cso2-dev
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
        ├── secrets.env     # ❌ gitignored - actual secrets
        ├── secrets.env.example  # ✅ committed - template
        ├── content-service.yaml
        ├── user-identity-service.yaml
        └── ... (8 services + frontend)
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
- **Secrets** = Sensitive data (passwords, API keys) - NEVER commit `secrets.env`
- **envFrom** = Inject all ConfigMap/Secret values into pods

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
