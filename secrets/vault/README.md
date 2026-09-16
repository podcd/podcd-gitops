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

This writes three KV secrets using the dev root token (`dev-root-token`):

| Path | Fields |
|---|---|
| `secret/demo/db` | `password`, `username` |
| `secret/demo/api` | `api_key`, `region` |
| `secret/demo/tls` | `certificate`, `private_key`, `ca` |

## Step 3 - configure the token and deploy demo-app

```bash
# Add the Vault token to agent.env (0600, never in Git)
printf 'VAULT_TOKEN=dev-root-token\n' >> ~/.config/podcd/agent.env

# Uncomment the apps in hosts.yaml:
sed -i 's/# - demo-app/- demo-app/; s/# - demo-tls-app/- demo-tls-app/' secrets/vault/hosts.yaml

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

## Secrets as files

`tls-files.yaml` covers what `demo-app` does not: the `ExternalSecret` produces a
Secret named differently from itself (`demo-tls` -> `demo-tls-material`), the Pod
mounts it as a volume so each key lands as a file, and one key is pulled into a
single variable with `secretKeyRef` rather than dragging everything in with
`envFrom`. Keys and certificates have no business in an environment variable,
where every child process and every `podman inspect` can read them.

```bash
podcd logs demo-tls-app
```



podcd reconcile   # detects manifest change, restarts demo-app
```

## Using AppRoles

Against an existing Vault, you will need an approle and an authrole with the correct policies and permissions on the paths it needs to provision.
```

```bash
sudo -u podcd bash -lc 'umask 077 && cat >> ~/.config/podcd/agent.env' <<'EOF'
VAULT_ROLE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
VAULT_SECRET_ID=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
EOF
```

**A store pointing at it.** Set `server:` on `vault-approle` in `stores.yaml`,
then aim each `ExternalSecret` at it:

```yaml
spec:
  secretStoreRef:
    name: vault-approle
```

## Tear down

```bash
podcd reconcile --prune   # or: podcd prune --all
```
