# Secrets examples

The subfolders are self-contained examples, one per secret backend. Each lives in its own subdirectory; point the agent at it with `podcd config set path secrets/<dir>`.

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

The agent's provision phase resolves every `ExternalSecret` before compiling
workloads. The resolved `v1/Secret` is bundled into the pod's kube manifest
(0600), so `podman kube play` receives a complete, playable document. Rotating
a secret value changes the manifest hash and triggers a pod restart on the next
reconcile.

---

## Quick-start for each backend

### env-store - values from agent.env

```bash
podcd config set path secrets/env-store
printf 'DEMO_DB_PASSWORD=hunter2\nDEMO_API_TOKEN=tok-demo-1234\n' \
  >> ~/.config/podcd/agent.env
podcd reconcile
podcd logs demo-app
```

### file-store - values from files

```bash
podcd config set path secrets/file-store
mkdir -p /run/secrets/demo
printf 'hunter2'       | install -m 0600 /dev/stdin /run/secrets/demo/db_password
printf 'tok-demo-1234' | install -m 0600 /dev/stdin /run/secrets/demo/api_token
podcd reconcile
podcd logs demo-app
```

### vault - values from HashiCorp Vault

```bash
podcd config set path secrets/vault

# Stage 1: start Vault (managed by podcd)
podcd reconcile

# Stage 2: seed demo data
./secrets/vault/seed-vault.sh

# Stage 3: add token, enable demo-app
printf 'VAULT_TOKEN=dev-root-token\n' >> ~/.config/podcd/agent.env
sed -i 's/# - demo-app/- demo-app/' secrets/vault/hosts.yaml
podcd reconcile
podcd logs demo-app
```

See each subdirectory's `README.md` for rotation instructions and further details.
