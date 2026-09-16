# Secrets examples

The subfolders are self-contained examples, one per secret backend. Each lives in its own subdirectory; point the agent at it with `podcd config set repo-path secrets/<dir>`.

| Example | Backend | Use when |
|---|---|---|
| [`env-store/`](env-store/) | Agent environment (`agent.env`) | Values you set manually or inject via CI/CD |
| [`file-store/`](file-store/) | Files on disk | A secrets agent, Ansible, or Terraform writes files |
| [`vault/`](vault/) | HashiCorp Vault KV v2 | Centralised secrets management; Vault managed by podcd |

All three follow the same pattern in Git:

```yaml
# 1. A SecretStore declares where values come from
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: my-store
spec:
  provider:
    env: {}   # or file: / vault:

# 2. An ExternalSecret names which keys to fetch
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-secret
spec:
  secretStoreRef:
    name: my-store
  target:
    name: my-secret   # v1/Secret name the pod references
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: DB_PASSWORD   # var name / filename / vault path

# 3. The pod references the secret by name, as standard Kubernetes API
```

The agent fetches a secret while it compiles this host's workloads, and only
the ones those workloads reference: a store nobody on this machine uses is
never contacted. The resolved `v1/Secret` is bundled into the pod's kube
manifest (0600), so `podman kube play` receives a complete, playable document.
Rotating a value in the backend changes the manifest hash and restarts the pod
on the next reconcile.

---

## Quick-start for each backend

### env-store - values from agent.env

```bash
podcd config set repo-path secrets/env-store
printf 'DEMO_DB_PASSWORD=hunter2\nDEMO_API_TOKEN=tok-demo-1234\n' \
  >> ~/.config/podcd/agent.env
podcd reconcile
podcd logs demo-app
```

### file-store - values from files

```bash
podcd config set repo-path secrets/file-store
mkdir -p /run/secrets/demo
printf 'hunter2'       | install -m 0600 /dev/stdin /run/secrets/demo/db_password
printf 'tok-demo-1234' | install -m 0600 /dev/stdin /run/secrets/demo/api_token
podcd reconcile
podcd logs demo-app
```

### vault - values from HashiCorp Vault

```bash
podcd config set repo-path secrets/vault

# Start Vault; its sidecar seeds the secrets and sets up the AppRole
podcd reconcile

# Give the agent the credentials it authenticates with
umask 077 && cat >> ~/.config/podcd/agent.env <<'EOF'
VAULT_TOKEN=dev-root-token
VAULT_ROLE_ID=podcd-demo-role-id
VAULT_SECRET_ID=podcd-demo-secret-id
EOF

# Uncomment the demo apps in hosts.yaml, then deploy them
podcd reconcile
podcd logs demo-app
```

See each subdirectory's `README.md` for rotation instructions and further details.
