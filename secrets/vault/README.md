# vault example

Demonstrates `ExternalSecret` + `SecretStore` with HashiCorp Vault KV v2 as the backend.

```
agent.env (token, role id + secret id) ──auth──▶ SecretStore (vault-dev, vault-approle)
                                                       │
                          ExternalSecret (demo-db, demo-api, demo-tls)
                                                       │ fetched while compiling
                                                v1/Secret (resolved)
                                                       │
                                   pod manifest ──podman kube play──▶ containers
```

## Step 1 - point the agent at this example

```bash
podcd install                                   # systemd user service
systemctl --user enable --now podcd-agent

podcd config create --force \
  --repo-url https://github.com/podcd/podcd-gitops.git \
  --repo-path secrets/vault \
  --host local
```

## Step 2 - start Vault

`hosts.yaml` begins with `vault-dev` alone, so the first reconcile brings up the
dev server and nothing else:

```bash
podcd reconcile
curl -s http://127.0.0.1:8200/v1/sys/health | grep initialized
```

Its `vault-seed` sidecar does the setup for you once Vault answers its readiness
check - there is nothing to seed by hand. It writes three KV secrets:

| Path | Fields |
|---|---|
| `secret/demo/db` | `password`, `username` |
| `secret/demo/api` | `api_key`, `region` |
| `secret/demo/tls` | `certificate`, `private_key`, `ca` |

and configures an AppRole: the `approle` auth method, a `podcd-demo` policy
granting `read` on `secret/data/demo/*` and nothing else, and a `podcd-demo`
role with a pinned role id and secret id.

## Step 3 - give the agent its credentials

The one manual step. These are the values the sidecar pinned; paste the block as
is (0600, never in Git):

```bash
umask 077 && cat >> ~/.config/podcd/agent.env <<'EOF'
VAULT_TOKEN=dev-root-token
VAULT_ROLE_ID=podcd-demo-role-id
VAULT_SECRET_ID=podcd-demo-secret-id
EOF
```

| Variable | Used by |
|---|---|
| `VAULT_TOKEN` | the `vault-dev` store - `demo-db`, `demo-api` |
| `VAULT_ROLE_ID`, `VAULT_SECRET_ID` | the `vault-approle` store - `demo-tls` |

Both stores point at the same Vault, so one reconcile exercises a token and an
AppRole side by side.

## Step 4 - deploy the demo apps

```bash
# Uncomment the apps in hosts.yaml:
sed -i 's/# - demo-app/- demo-app/; s/# - demo-tls-app/- demo-tls-app/' secrets/vault/hosts.yaml

# Reconcile: secrets are fetched from Vault, then the pods start
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

`pod-with-secret-from-vault.yaml` covers what `demo-app` does not: the `ExternalSecret` produces a
Secret named differently from itself (`demo-tls` -> `demo-tls-material`), the Pod
mounts it as a volume so each key lands as a file, and one key is pulled into a
single variable with `secretKeyRef` rather than dragging everything in with
`envFrom`. Keys and certificates have no business in an environment variable,
where every child process and every `podman inspect` can read them.

```bash
podcd logs demo-tls-app
```

## Using AppRoles

Against an existing Vault, you will need an approle and an authrole with the correct policies and permissions on the paths it needs to provision.

```bash
vault auth enable approle

vault policy write podcd-demo - <<'EOF'
path "secret/data/demo/*" {
  capabilities = ["read"]
}
EOF

vault write auth/approle/role/podcd-demo \
  token_policies=podcd-demo token_ttl=1h token_max_ttl=4h

vault read  -field=role_id      auth/approle/role/podcd-demo/role-id
vault write -f -field=secret_id auth/approle/role/podcd-demo/secret-id
```

Put the two values on the host:

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
