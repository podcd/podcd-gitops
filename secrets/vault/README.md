# vault example

Demonstrates `ExternalSecret` + `SecretStore` with HashiCorp Vault KV v2 as the backend.

```
agent.env (VAULT_TOKEN) ──auth──▶ SecretStore (vault)
                                        │
                              ExternalSecret (demo-db, demo-api)
                                        │ provision phase
                                  v1/Secret (resolved)
                                        │
                             pod manifest ──podman kube play──▶ containers
```

## Step 1 - start Vault

```bash
# Point the agent at this example
podcd config set path secrets/vault

# Deploy the vault-dev pod (hosts.yaml starts with vault-dev only)
podcd reconcile

# Verify vault is up
curl -s http://127.0.0.1:8200/v1/sys/health | grep initialized
```

## Step 2 - seed Vault with demo secrets

```bash
./secrets/vault/seed-vault.sh
```

This writes two KV secrets using the dev root token (`dev-root-token`):

| Path | Fields |
|---|---|
| `secret/demo/db` | `password`, `username` |
| `secret/demo/api` | `api_key`, `region` |

## Step 3 - configure the token and deploy demo-app

```bash
# Add the Vault token to agent.env (0600, never in Git)
printf 'VAULT_TOKEN=dev-root-token\n' >> ~/.config/podcd/agent.env

# Uncomment demo-app in hosts.yaml:
sed -i 's/# - demo-app/- demo-app/' secrets/vault/hosts.yaml

# Reconcile: provision phase reads from Vault, demo-app starts
podcd reconcile
```

## Step 4 - verify

```bash
podcd logs demo-app
```

Expected output:

```
=== secrets from vault ===
DB_PASSWORD  set: yes
DB_USERNAME  set: yes
api_key      set: yes
```

## Rotation

Update a secret in Vault and reconcile. The provision phase re-fetches the
value, the manifest hash changes, and the pod restarts.

```bash
curl -s -X POST http://127.0.0.1:8200/v1/secret/data/demo/db \
  -H "X-Vault-Token: dev-root-token" \
  -H "Content-Type: application/json" \
  -d '{"data": {"password": "rotated-secret", "username": "demo-app"}}'

podcd reconcile   # detects manifest change, restarts demo-app
```

## Using AppRole instead of a token

For production, replace the static token with AppRole credentials. Both stay
in `agent.env` and are never in Git:

```yaml
# stores.yaml
auth:
  appRole:
    roleId: env:VAULT_ROLE_ID
    secretRef:
      name: env:VAULT_SECRET_ID
```

```bash
# agent.env
VAULT_ROLE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
VAULT_SECRET_ID=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
```

## Tear down

```bash
podcd reconcile --prune   # or: podcd prune --all
```
