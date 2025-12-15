docker run -d --name vault \
  --cap-add=IPC_LOCK \
  -p 8200:8200 \
  -v "$PWD/config:/vault/config" \
  -v "$PWD/file:/vault/file" \
  hashicorp/vault server