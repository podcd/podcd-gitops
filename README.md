# podcd-gitops

This repository is a small example of how to define container workloads with podcd.

There is no prescribed directory structure. Organize the Git repository however you like.

## Configuration model

podcd builds a host's desired state from several layers:

```text
Pod
       ↓
Environment
       ↓
Group(s)
       ↓
Host
```

`Pod` defines a workload. `Environment`, `Group`, and `Host` determine **which workloads run on a host** and can override their configuration.

## Pod

A workload is a plain Kubernetes `Pod`, played by podman through a Quadlet `.kube` unit:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: local
  annotations:
    io.podcd.networks: "edge"   # no Kubernetes field for this; becomes Network= on the unit
spec:
  restartPolicy: Always
  containers:
    - name: nginx
      image: docker.io/library/nginx@sha256:...
      ports:
        - containerPort: 80
          hostPort: 8080
          hostIP: 127.0.0.1
      resources:
        limits:
          memory: 256Mi
      livenessProbe:                # podman runs this; podcd reports the verdict
        httpGet: { path: /, port: 80 }
```

The pod defines **what it is**, not which hosts run it.


## Host

A `Host` selects what should run on a particular machine:

```yaml
apiVersion: gitops.podcd.io/v1
kind: Host
metadata:
  name: local
spec:
  applications:
    - local
    - local-pod
```

For this example, the host directly selects both workloads.

The resulting desired state is:

```text
local
local-pod
```

## Groups and environments

For larger repositories, applications can be selected indirectly.

A group might contain:

```yaml
apiVersion: gitops.podcd.io/v1
kind: Group
metadata:
  name: web
spec:
  applications:
    - nginx
    - node-exporter
```

A host can then use the group:

```yaml
spec:
  groups:
    - web
```

The host gets all applications selected by the group.

Applications can also be added directly:

```yaml
spec:
  groups:
    - web
  applications:
    - my-api
```

The final set is the union of everything selected by the environment, groups, and host.

## Removing an application

A host can remove an application selected by an environment or group:

```yaml
spec:
  groups:
    - web
  excludeApplications:
    - node-exporter
```

`excludeApplications` is applied after selection, so the application disappears from the host's desired state.

If the application was not selected in the first place, podcd reports an error rather than silently ignoring the entry.

## Overrides

A host or group can override an application's configuration:

```yaml
spec:
  groups:
    - web
  overrides:
    nginx:
      spec:
        containers:
          - name: nginx
            ports:
              - containerPort: 80
                hostPort: 9090
```

The base `nginx` application is unchanged. Only the resolved configuration for this host is different.

## Override precedence

When an application is overridden at multiple levels, later layers win:

```text
Pod
    ↓
Environment
    ↓
Group 1
    ↓
Group 2
    ↓
Host
```

Groups are processed in the order listed by the host:

```yaml
groups:
  - base
  - web
```

Therefore `web` overrides `base`, and the host overrides both.

For example:

```yaml
# base group
overrides:
  nginx:
    spec:
      restartPolicy: Always
```

```yaml
# web group
overrides:
  nginx:
    spec:
      containers:
        - name: nginx
          ports:
            - containerPort: 80
              hostPort: 8080
```

```yaml
# host
overrides:
  nginx:
    spec:
      containers:
        - name: nginx
          ports:
            - containerPort: 80
              hostPort: 9090
```

The resolved pod becomes:

```text
restartPolicy: Always
port: 9090 -> 80
```

## Merge rules

An override is a **strategic merge patch** against the Pod, so it follows Kubernetes' own rules rather than any podcd invention. Containers merge by `name`, ports by `containerPort`, environment variables by `name`, and a plain list is replaced wholesale.

Changing one variable leaves the rest alone:

```yaml
# pod
containers:
  - name: nginx
    env:
      - {name: LOG_LEVEL, value: info}
      - {name: PORT, value: "8080"}
```

```yaml
# host override
spec:
  containers:
    - name: nginx
      env:
        - {name: LOG_LEVEL, value: debug}
```

```yaml
# result
containers:
  - name: nginx
    env:
      - {name: LOG_LEVEL, value: debug}
      - {name: PORT, value: "8080"}
```

A list with no merge key - `command`, `args` - is replaced entirely, so overriding it means writing the whole list.

## Values templating

Overrides parametrize by naming an application, so they can't help when an application only exists on some hosts. Values templating parametrizes the document itself instead: a file named `*.tpl` is a Go template, rendered per host against `.Values` and only then read as a document. It is the name that makes it a template - `{{` in a plain `.yaml` is just text.

```yaml
# applications/edge-api.yaml.tpl
apiVersion: v1
kind: Pod
metadata:
  name: edge-api
spec:
  containers:
    - name: edge-api
      image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```

Which values apply can be declared in Git, on the `Host`, `Group` or `Environment` that selects the application - the same precedence as an override (environment, then groups in listed order, then the host, host winning):

```yaml
apiVersion: gitops.podcd.io/v1
kind: Environment
metadata:
  name: prod
spec:
  applications: [edge-api]
  values:
    - values/prod.yaml
```

You can alternatively define value files in the `agent.yaml` as well.

Because a template is rendered before anything reads it, it may use all of Go's `text/template`. It may render any deployable kind (`Pod`, `ConfigMap`, `Secret`), but not a `Host`, `Group` or `Environment`, since those decide a host's values in the first place. One consequence: inside a `.tpl`, a YAML `#` comment is still template text, so a comment that quotes template syntax literally (a bare `{{ if }}`) fails to parse - write it as a Go template comment, `{{/* like this */}}`, which renders to nothing.

## Resolution and reconciliation

podcd first compiles all of these definitions into a **fully resolved desired state** for the target host.

```text
Git repository
      ↓
Resolve
      ↓
DesiredState
      ↓
ActualState
      ↓
Plan
      ↓
create / update / delete / restart
```

The planner does not deal with inheritance. By the time planning starts, every application contains its final configuration.

For example, removing an inherited application does not directly issue a remove command. It simply means the application is absent from `DesiredState`; the planner then detects that it exists in the actual state and generates a delete action.

## Try it

[`minimal/`](./minimal) contains a `local` host running nginx on port `8080` - the smallest complete example, one Pod, one Host, no groups or environments. Point an agent at it (`--repo-path minimal`, or `path: minimal` in `agent.yaml`) and:

```bash
podcd validate
podcd plan
podcd reconcile
podcd status
```

Then:

```bash
curl http://127.0.0.1:8080/
```

Change a definition in Git and reconcile again:

```text
Git change
   ↓
resolve
   ↓
new DesiredState
   ↓
plan
   ↓
reconcile
```

[`secrets/`](./secrets) has three self-contained examples of the ExternalSecret + SecretStore pattern - one for each backend (env, file, vault).
