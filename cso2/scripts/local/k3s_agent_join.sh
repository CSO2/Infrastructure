#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <server-ip-or-dns> <token> <agent-node-ip> [extra-k3s-agent-args]"
  echo "Example: $0 192.168.1.20 K10a...def 192.168.1.21"
  exit 1
fi

SERVER_IP="$1"
TOKEN="$2"
AGENT_IP="$3"
shift 3
EXTRA_ARGS="${*:-}"

if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (use sudo)."
  exit 1
fi

echo "Joining K3s cluster at https://${SERVER_IP}:6443 from agent ${AGENT_IP} ..."

export K3S_URL="https://${SERVER_IP}:6443"
export K3S_TOKEN="${TOKEN}"
export INSTALL_K3S_EXEC="agent \
  --node-ip ${AGENT_IP} \
  ${EXTRA_ARGS}"

curl -sfL https://get.k3s.io | sh -

echo
echo "K3s agent installation complete on ${AGENT_IP}."
echo "You can check node status from the server with:"
echo "  sudo k3s kubectl get nodes"
echo
