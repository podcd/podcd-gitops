#!/usr/bin/env bash
# Seed the dev Vault instance with example secrets.
# Requires curl. Run once after 'podcd reconcile' starts the vault-dev pod.
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-dev-root-token}"
AUTH="-H \"X-Vault-Token: $VAULT_TOKEN\""

echo "Waiting for Vault at $VAULT_ADDR ..."
for i in $(seq 1 30); do
  if curl -sf "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
    echo "Vault is ready."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "Vault did not become ready in 60s. Is the vault-dev pod running?"
    exit 1
  fi
  sleep 2
done

kv_put() {
  local path="$1"; shift
  local payload="{\"data\": {"
  local first=true
  for kv in "$@"; do
    key="${kv%%=*}"; val="${kv#*=}"
    $first || payload+=","
    payload+="\"$key\": \"$val\""
    first=false
  done
  payload+="}}"
  curl -sf -X POST "$VAULT_ADDR/v1/$path" \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" >/dev/null
  echo "  written $path"
}

echo "Seeding secrets ..."
kv_put "secret/data/demo/db"  "password=vault-demo-hunter2" "username=demo-app"
kv_put "secret/data/demo/api" "api_key=vault-demo-api-key-1234" "region=us-east-1"

echo ""
echo "Done. Secrets written:"
echo "  secret/demo/db  -> password, username"
echo "  secret/demo/api -> api_key, region"
echo ""
echo "Next steps:"
echo "  printf 'VAULT_TOKEN=dev-root-token\\n' >> ~/.config/podcd/agent.env"
echo "  # Uncomment demo-app in hosts.yaml, then:"
echo "  podcd reconcile"
