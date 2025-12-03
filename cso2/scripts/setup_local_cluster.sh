#!/bin/bash
set -e

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
}

# Start Minikube
start_minikube() {
  echo "Starting Minikube..."
  minikube start --driver=docker --cpus=4 --memory=8192
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
  
  # Install Istio base (CRDs)
  echo "Installing Istio base components (CRDs)..."
  helm install istio-base istio/base \
    -n istio-system \
    --create-namespace \
    --set defaultRevision=default \
    --wait
  
  # Validate CRD installation
  echo "Validating CRD installation..."
  helm ls -n istio-system
  
  # Install Istiod (control plane)
  echo "Installing Istiod (Istio discovery service)..."
  helm install istiod istio/istiod \
    -n istio-system \
    --set pilot.resources.requests.cpu=100m \
    --set pilot.resources.requests.memory=256Mi \
    --set pilot.resources.limits.cpu=500m \
    --set pilot.resources.limits.memory=512Mi \
    --wait
  
  # Verify Istiod installation
  echo "Verifying Istiod installation..."
  helm status istiod -n istio-system
  kubectl get deployments -n istio-system --output wide
  
  # Install Istio Ingress Gateway
  echo "Installing Istio Ingress Gateway..."
  kubectl create namespace istio-ingress --dry-run=client -o yaml | kubectl apply -f -
  helm install istio-ingressgateway istio/gateway \
    -n istio-ingress \
    --set resources.requests.cpu=100m \
    --set resources.requests.memory=128Mi \
    --set resources.limits.cpu=500m \
    --set resources.limits.memory=256Mi \
    --wait
  
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

# Deploy CSO2 application
deploy_cso2() {
  echo "Deploying CSO2 application..."
  
  # Get the directory where the script is located
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  K8S_DIR="$(dirname "$SCRIPT_DIR")/k8s"
  
  # Check if .env exists
  if [ ! -f "$K8S_DIR/overlays/dev/.env" ]; then
    echo "⚠️  .env not found. Creating from .env.example..."
    cp "$K8S_DIR/overlays/dev/.env.example" "$K8S_DIR/overlays/dev/.env"
    echo "⚠️  Please edit $K8S_DIR/overlays/dev/.env with your actual secrets"
    echo ""
    echo "Generate JWT keys with:"
    echo "  openssl genrsa -out private_key.pem 4096"
    echo "  openssl rsa -in private_key.pem -pubout -out public_key.pem"
    echo ""
    read -p "Press Enter after updating .env file to continue..."
  fi
  
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
  # verify_minikube
  install_istio
  deploy_cso2
  show_access_info
}

main