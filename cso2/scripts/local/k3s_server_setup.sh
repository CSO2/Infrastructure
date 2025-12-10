#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <server-ip-or-dns> [extra-k3s-server-args]"
  echo "Example: $0 192.168.1.20 --disable traefik"
  exit 1
fi

SERVER_IP="$1"
shift || true
EXTRA_ARGS="${*:-}"

if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (use sudo)."
  exit 1
fi

echo "Installing K3s server on ${SERVER_IP} ..."

# INSTALL_K3S_EXEC controls what k3s setup script runs
export INSTALL_K3S_EXEC="server \
  --node-ip ${SERVER_IP} \
  --tls-san ${SERVER_IP} \
  ${EXTRA_ARGS}"

curl -sfL https://get.k3s.io | sh -

echo
echo "K3s server installation complete."
echo

echo "Kubeconfig is at: /etc/rancher/k3s/k3s.yaml"
echo "You can copy it to your user kube config with:"
echo "  sudo cp /etc/rancher/k3s/k3s.yaml \$HOME/.kube/config"
echo "  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
echo

echo "Node join token (use this on agents):"
cat /var/lib/rancher/k3s/server/node-token
echo
