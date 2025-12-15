#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Install prerequisites
install_prerequisites() {
  echo "Installing prerequisites..."

  # Update package list
  sudo apt-get update

  # Install curl if not installed
  if ! command_exists curl; then
    echo "Installing curl..."
    sudo apt-get install -y curl
  fi

  # Install Docker if not installed
  if ! command_exists docker; then
    echo "Installing Docker..."
    sudo apt-get install -y docker.io
  fi

  # Install Minikube if not installed
  if ! command_exists minikube; then
    echo "Installing Minikube..."
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm minikube-linux-amd64
  fi

  # Install kubectl if not installed
  if ! command_exists kubectl; then
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
  fi

  # Install kustomize if not installed
  if ! command_exists kustomize; then
    echo "Installing kustomize..."
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    sudo mv kustomize /usr/local/bin/
  fi

  # Install Helm if not installed
  if ! command_exists helm; then
    echo "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi

  # Install Vault CLI if not installed
  if ! command_exists vault; then
    echo "Installing Vault CLI..."
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
      sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y vault
  fi
}

# Start Minikube
start_minikube() {
  echo "Starting Minikube..."
  minikube start --driver=docker --cpus=12 --memory=7096
}

start_local_vault() {
  echo "Starting local Vault container (host network)..."
  "$SCRIPT_DIR/start_dev_vault.sh"
}

# Verify Minikube setup
verify_minikube() {
  echo "Verifying Minikube setup..."
  kubectl get nodes
}

# Install Istio
install_istio() {
  echo "Installing Istio..."
  
  # Add Istio Helm repository
  echo "Adding Istio Helm repository..."
  helm repo add istio https://istio-release.storage.googleapis.com/charts
  helm repo update
  
  helm install istio-base istio/base -n istio-system --set defaultRevision=default --create-namespace
  helm install istiod istio/istiod -n istio-system --wait
  kubectl create namespace istio-ingress
  helm install istio-ingress istio/gateway -n istio-ingress 
  
  # Create and label cso2-dev namespace for automatic sidecar injection
  echo "Creating cso2-dev namespace with Istio sidecar injection..."
  kubectl create namespace cso2-dev --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace cso2-dev istio-injection=enabled --overwrite
  
  echo "✅ Istio installed successfully!"
  echo ""
  echo "Istio components status:"
  kubectl get pods -n istio-system
  kubectl get pods -n istio-ingress
}

install_external_secrets() {
  echo "Installing External Secrets Operator..."

  if ! helm repo list | grep -q 'external-secrets'; then
    helm repo add external-secrets https://charts.external-secrets.io
  fi

  helm repo update external-secrets || helm repo update

  kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

  helm upgrade --install external-secrets external-secrets/external-secrets \
    -n external-secrets \
    --set installCRDs=true \
    --wait

  echo "External Secrets Operator status:"
  kubectl get pods -n external-secrets
}

configure_vault_kubernetes_auth() {
  if [ "${SKIP_VAULT_CONFIG:-false}" = "true" ]; then
    echo "Skipping Vault Kubernetes auth configuration (SKIP_VAULT_CONFIG=true)."
    return
  fi

  if [ -z "${VAULT_TOKEN:-}" ]; then
    echo "VAULT_TOKEN is not set. Export a token with permissions to configure Vault and rerun to automate Kubernetes auth."
    return
  fi

  export VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"

  if ! vault status >/dev/null 2>&1; then
    echo "Vault is not reachable at ${VAULT_ADDR}. Skipping Kubernetes auth configuration."
    return
  fi

  echo "Configuring Vault Kubernetes auth..."

  vault secrets enable -path=secret kv-v2 >/dev/null 2>&1 || true
  vault auth enable kubernetes >/dev/null 2>&1 || true

  local sa_namespace="${EXTERNAL_SECRETS_NAMESPACE:-external-secrets}"
  local sa_name="${EXTERNAL_SECRETS_SERVICE_ACCOUNT:-external-secrets}"

  echo "Fetching Kubernetes service account token for ${sa_namespace}/${sa_name}..."
  local sa_secret=""
  for attempt in {1..10}; do
    sa_secret=$(kubectl get sa "$sa_name" -n "$sa_namespace" -o jsonpath='{.secrets[0].name}' 2>/dev/null || true)
    [ -n "$sa_secret" ] && break
    sleep 2
  done

  if [ -z "$sa_secret" ]; then
    echo "Unable to find service account secret for ${sa_namespace}/${sa_name}. Ensure the External Secrets Operator finished installing."
    return
  fi

  local token host ca
  token=$(kubectl get secret "$sa_secret" -n "$sa_namespace" -o jsonpath='{.data.token}' | base64 -d)
  host=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.server}')
  ca=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

  vault write auth/kubernetes/config \
    token_reviewer_jwt="$token" \
    kubernetes_host="$host" \
    kubernetes_ca_cert="$ca"

  cat <<'EOF' | vault policy write cso2-dev-external-secrets -
path "secret/data/cso2/dev/*" {
  capabilities = ["read"]
}
EOF

  cat <<'EOF' | vault policy write cso2-prod-external-secrets -
path "secret/data/cso2/prod/*" {
  capabilities = ["read"]
}
EOF

  vault write auth/kubernetes/role/cso2-dev-external-secrets \
    bound_service_account_names="${sa_name}" \
    bound_service_account_namespaces="${sa_namespace}" \
    policies=cso2-dev-external-secrets \
    ttl=1h

  vault write auth/kubernetes/role/cso2-prod-external-secrets \
    bound_service_account_names="${sa_name}" \
    bound_service_account_namespaces="${sa_namespace}" \
    policies=cso2-prod-external-secrets \
    ttl=1h

  echo "Vault Kubernetes auth configured."
}

generate_jwt_pair() {
  local private_file
  private_file=$(mktemp)
  local public_file
  public_file=$(mktemp)

  openssl genrsa -out "$private_file" 4096 >/dev/null 2>&1
  openssl rsa -in "$private_file" -pubout -out "$public_file" >/dev/null 2>&1

  DEV_JWT_PRIVATE=$(awk '{printf "%s\\n", $0}' "$private_file" | sed 's/\\n$//')
  DEV_JWT_PUBLIC=$(awk '{printf "%s\\n", $0}' "$public_file" | sed 's/\\n$//')

  rm -f "$private_file" "$public_file"
}

seed_dev_vault_secrets() {
  if [ "${SKIP_VAULT_SEEDING:-false}" = "true" ]; then
    echo "Skipping Vault secret seeding (SKIP_VAULT_SEEDING=true)."
    return
  fi

  if [ -z "${VAULT_TOKEN:-}" ]; then
    echo "VAULT_TOKEN is not set. Export a token with permissions to write KV secrets to automate seeding."
    return
  fi

  export VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"

  if ! vault status >/dev/null 2>&1; then
    echo "Vault is not reachable at ${VAULT_ADDR}. Skipping secret seeding."
    return
  fi

  echo "Seeding development secrets into Vault (sample values only)..."
  generate_jwt_pair

  vault kv put secret/cso2/dev/redis \
    REDIS_PASSWORD="${DEV_REDIS_PASSWORD:-changeme}"

  vault kv put secret/cso2/dev/postgresql \
    POSTGRES_USER="${DEV_POSTGRES_USER:-postgres}" \
    POSTGRES_PASSWORD="${DEV_POSTGRES_PASSWORD:-changeme}" \
    CSO2_USER="${DEV_CSO2_DB_USER:-cso2}" \
    CSO2_PASSWORD="${DEV_CSO2_DB_PASSWORD:-changeme}"

  vault kv put secret/cso2/dev/mongodb \
    MONGO_INITDB_ROOT_USERNAME="${DEV_MONGO_ROOT_USER:-admin}" \
    MONGO_INITDB_ROOT_PASSWORD="${DEV_MONGO_ROOT_PASSWORD:-changeme}"

  vault kv put secret/cso2/dev/user-identity-service \
    DATABASE_PASSWORD="${DEV_USER_IDENTITY_DB_PASSWORD:-changeme}" \
    MONGODB_URI="${DEV_USER_IDENTITY_MONGO_URI:-mongodb://admin:changeme@mongodb:27017/cso2_user_identity}" \
    JWT_PRIVATE_KEY="$DEV_JWT_PRIVATE" \
    JWT_PUBLIC_KEY="$DEV_JWT_PUBLIC"

  vault kv put secret/cso2/dev/product-catalogue-service \
    MONGODB_URI="${DEV_CATALOG_MONGO_URI:-mongodb://admin:changeme@mongodb:27017/CSO2_product_catalogue_service?authSource=admin}"

  vault kv put secret/cso2/dev/order-service \
    DATABASE_PASSWORD="${DEV_ORDER_DB_PASSWORD:-changeme}"

  vault kv put secret/cso2/dev/shoppingcart-wishlist-service \
    MONGODB_URI="${DEV_CART_MONGO_URI:-mongodb://admin:changeme@mongodb:27017/CSO2_shoppingcart_wishlist_service}" \
    REDIS_PASSWORD="${DEV_REDIS_PASSWORD:-changeme}"

  vault kv put secret/cso2/dev/support-service \
    DATABASE_PASSWORD="${DEV_SUPPORT_DB_PASSWORD:-changeme}" \
    MONGODB_URI="${DEV_SUPPORT_MONGO_URI:-mongodb://admin:changeme@mongodb:27017/CSO2_support_service?authSource=admin}" \
    ORDER_SERVICE_URL="${DEV_ORDER_SERVICE_URL:-http://order-service:8083}"

  vault kv put secret/cso2/dev/content-service \
    MONGODB_URI="${DEV_CONTENT_MONGO_URI:-mongodb://admin:changeme@mongodb:27017/CSO2_content_service?authSource=admin}"

  vault kv put secret/cso2/dev/notifications-service \
    MONGODB_URI="${DEV_NOTIFICATIONS_MONGO_URI:-mongodb://admin:changeme@mongodb:27017/CSO2_notifications_service?authSource=admin}" \
    MAIL_USERNAME="${DEV_MAIL_USERNAME:-your-email@gmail.com}" \
    MAIL_PASSWORD="${DEV_MAIL_PASSWORD:-your-app-password}" \
    ADMIN_EMAIL="${DEV_ADMIN_EMAIL:-admin@cso2.com}" \
    TWILIO_ACCOUNT_SID="${DEV_TWILIO_ACCOUNT_SID:-}" \
    TWILIO_AUTH_TOKEN="${DEV_TWILIO_AUTH_TOKEN:-}" \
    TWILIO_PHONE_NUMBER="${DEV_TWILIO_PHONE_NUMBER:-}" \
    FIREBASE_CONFIG_PATH="${DEV_FIREBASE_CONFIG_PATH:-classpath:firebase-service-account.json}"

  vault kv put secret/cso2/dev/reporting-and-analysis-service \
    DATABASE_PASSWORD="${DEV_REPORTING_DB_PASSWORD:-changeme}"

  echo "Sample development secrets stored in Vault. Replace these values with secure credentials before using non-local environments."
}

# Deploy CSO2 application
deploy_cso2() {
  echo "Deploying CSO2 application..."
  
  K8S_DIR="$SCRIPT_DIR/../../k8s"
  
  # Ensure cso2-dev namespace exists (with Istio injection label)
  echo "Ensuring cso2-dev namespace exists..."
  kubectl create namespace cso2-dev --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace cso2-dev istio-injection=enabled --overwrite

  echo ""
  echo "Make sure Vault is running and contains the secrets referenced under overlays/dev/secrets/* before continuing."
  echo "Press Ctrl+C to abort and seed Vault if needed."
  sleep 3

  # Apply Kustomize manifests
  echo "Applying Kustomize manifests..."
  kubectl apply -k "$K8S_DIR/overlays/dev"
  
  echo "✅ CSO2 application deployed!"
  echo ""
  echo "Checking deployment status..."
  kubectl get pods -n cso2-dev
  echo ""
  kubectl get virtualservices -n cso2-dev
  kubectl get gateway -n cso2-dev
}

# Show access information
show_access_info() {
  echo ""
  echo "========================================="
  echo "🎉 Setup Complete!"
  echo "========================================="
  echo ""
  echo "Minikube cluster is running with Istio and CSO2 deployed."
  echo ""
  echo "Useful commands:"
  echo "  - View all pods:           kubectl get pods -n cso2-dev"
  echo "  - View services:           kubectl get svc -n cso2-dev"
  echo "  - View Istio components:   kubectl get pods -n istio-system"
  echo "  - View Istio gateway:      kubectl get pods -n istio-ingress"
  echo "  - View Istio routes:       kubectl get virtualservices -n cso2-dev"
  echo "  - View logs:               kubectl logs -n cso2-dev deployment/<service-name>"
  echo "  - Minikube dashboard:      minikube dashboard"
  echo ""
  echo "To access the Istio ingress gateway:"
  echo "  1. Run in a separate terminal: minikube tunnel"
  echo "  2. Get gateway IP: kubectl get svc -n istio-ingress"
  echo "  3. Access API at: http://<GATEWAY-IP>/api/"
  echo ""
  echo "Example API calls:"
  echo "  - Public endpoint:  curl http://<GATEWAY-IP>/api/products"
  echo "  - Login:            curl -X POST http://<GATEWAY-IP>/api/auth/login \\"
  echo "                        -H 'Content-Type: application/json' \\"
  echo "                        -d '{\"email\":\"user@example.com\",\"password\":\"password\"}'"
  echo ""
}

# Main script execution
main() {
  echo "========================================="
  echo "CSO2 Minikube Cluster Setup"
  echo "========================================="
  echo ""
  
  # install_prerequisites
  # start_minikube
  # start_local_vault
  # verify_minikube
  # install_istio
  # install_external_secrets
  # configure_vault_kubernetes_auth
  # seed_dev_vault_secrets
  deploy_cso2
  show_access_info
}

main
