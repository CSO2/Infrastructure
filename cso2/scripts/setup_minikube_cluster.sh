#!/bin/bash
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
}

# Start Minikube
start_minikube() {
  echo "Starting Minikube..."
  minikube start --driver=docker
}

# Verify Minikube setup
verify_minikube() {
  echo "Verifying Minikube setup..."
  kubectl get nodes
}

# Main script execution
main() {
  install_prerequisites
  start_minikube
  verify_minikube
}

main