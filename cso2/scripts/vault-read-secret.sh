#!/bin/bash
# vault-read-secret.sh
# Helper to read any secret from Vault
# Usage: ./vault-read-secret.sh [namespace] [secret-path]
# Example: ./vault-read-secret.sh cso2-dev secret/cso2/postgresql

NAMESPACE=${1:-cso2-dev}
SECRET_PATH=${2:-secret/cso2/postgresql}

VAULT_POD=$(kubectl get pod -n "$NAMESPACE" -l app=vault -o jsonpath="{.items[0].metadata.name}")

kubectl exec -n "$NAMESPACE" "$VAULT_POD" -- \
  env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 \
  vault kv get "$SECRET_PATH"
