# env-store example

Reads secrets from the agent's environment (`~/.config/podcd/agent.env`) via an `ExternalSecret` + `SecretStore`.

```
SecretStore (env) + ExternalSecret -> v1/Secret -> use in pod manifest
```

## Try it

```bash
# 1. Point the agent at this example
podcd config set path secrets/env-store

# 2. Add the secret values to agent.env (0600, never in Git)
umask 077
printf 'DEMO_DB_PASSWORD=hunter2\nDEMO_API_TOKEN=tok-demo-1234\n' \
  >> ~/.config/podcd/agent.env

# 3. Preview what would change
podcd plan

# 4. Apply
podcd reconcile

# 5. Check the log – should print "yes" for both secrets
podcd logs demo-app
```

Expected log output:

```
=== secrets received ===
DB_PASSWORD set: yes
API_TOKEN  set: yes
```

## Rotation

Edit `~/.config/podcd/agent.env` and change a value. The next reconcile
detects the manifest change automatically and restarts the pod. No restart
of the agent is needed.

```bash
sed -i 's/DEMO_DB_PASSWORD=.*/DEMO_DB_PASSWORD=new-password/' \
  ~/.config/podcd/agent.env
podcd reconcile
```

## How it works

1. The provision phase runs `ExternalSecret` → `SecretStore(env)` → reads  `DEMO_DB_PASSWORD` and `DEMO_API_TOKEN` from the environment.
2. It writes a resolved `v1/Secret` named `app-secrets` to
   `~/.local/state/podcd/secrets/app-secrets.yaml` (0600).
3. That secret is bundled into the pod's kube manifest alongside the pod
   definition, then played by `podman kube play`.
4. The manifest hash changes whenever a secret value changes, so the next
   reconcile detects drift and restarts the pod.
