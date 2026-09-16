# file-store example

Reads secrets from files on disk. Use this when another tool (a secrets agent, Ansible, Terraform, a sidecar) writes one file per secret. The file store maps filenames to `Secret` keys.

```
/run/secrets/demo/db_password -> ExternalSecret provision -> v1/Secret bundled -> pod manifest
/run/secrets/demo/api_token
```

## Try it

```bash
# 1. Point the agent at this example
podcd config set repo-path secrets/file-store

# 2. Write the secret files (0600, never in Git)
mkdir -p /run/secrets/demo
printf 'hunter2'        | install -m 0600 /dev/stdin /run/secrets/demo/db_password
printf 'tok-demo-1234'  | install -m 0600 /dev/stdin /run/secrets/demo/api_token

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

Overwrite the file with a new value. The next reconcile detects the manifest
change and restarts the pod. No agent restart needed.

```bash
printf 'new-password' | install -m 0600 /dev/stdin /run/secrets/demo/db_password
podcd reconcile
```

## Loading a whole directory at once

To map every file in a directory to a Secret key without listing them
individually, use `dataFrom`:

```yaml
# external-secrets.yaml
spec:
  dataFrom:
    - extract:
        key: /run/secrets/demo   # each filename → Secret key, file content → value
```

Uncomment the `dataFrom` block (and remove the `data` block) in
[external-secrets.yaml](external-secrets.yaml) to try it.
