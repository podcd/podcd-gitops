# podcd GitOps Example

This repository is a small example of how to define container workloads with podcd.

The files are the **desired state**. podcd reads the repository, resolves the configuration for a host, validates it, and reconciles the result with the workloads running on that host.

There is no prescribed directory structure. Organize the Git repository however you like.

## Configuration model

podcd builds a host's desired state from several layers:

```text
Application / Pod
       ↓
Environment
       ↓
Group(s)
       ↓
Host
```

`Application` and `Pod` define workloads. `Environment`, `Group`, and `Host` determine **which workloads run on a host** and can override their configuration.

## Application

An `Application` defines a reusable workload:

```yaml
apiVersion: gitops.podcd.io/v1
kind: Application
metadata:
  name: local
spec:
  image: docker.io/library/nginx@sha256:...
  ports:
    - host: 8080
      container: 80
      hostIP: 127.0.0.1
  restartPolicy: always
```

The application defines **what it is**, not which hosts run it.

A `Pod` can be defined similarly:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: local-pod
spec:
  restartPolicy: Always
  containers:
    - name: nginx
      image: docker.io/library/nginx@sha256:...
      ports:
        - containerPort: 80
          hostPort: 8081
          hostIP: 127.0.0.1
```

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
      ports:
        - host: 9090
          container: 80
```

The base `nginx` application is unchanged. Only the resolved configuration for this host is different.

## Override precedence

When an application is overridden at multiple levels, later layers win:

```text
Application
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
    restartPolicy: always
```

```yaml
# web group
overrides:
  nginx:
    ports:
      - host: 8080
        container: 80
```

```yaml
# host
overrides:
  nginx:
    ports:
      - host: 9090
        container: 80
```

The resolved application becomes:

```text
restartPolicy: always
port: 9090 -> 80
```

## Merge rules

Overrides merge fields rather than replacing the entire application.

Maps are merged by key:

```yaml
# application
env:
  LOG_LEVEL: info
  PORT: "8080"
```

```yaml
# host override
env:
  LOG_LEVEL: debug
```

Result:

```yaml
env:
  LOG_LEVEL: debug
  PORT: "8080"
```

Lists are replaced as a whole. This applies to fields such as:

```text
ports
volumes
networks
command
entrypoint
```

So overriding `ports` replaces the application's complete port list.

## Values templating

Overrides parametrize by naming an application, so they can't help when an application only exists on some hosts. Values templating parametrizes the document itself instead: any file containing `{{` anywhere is rendered as a Go template against `.Values` before it's parsed.

```yaml
apiVersion: gitops.podcd.io/v1
kind: Application
metadata:
  name: edge-api
spec:
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

**Careful with comments, too.** The whole file becomes a template the moment it contains `{{` anywhere, YAML `#` comments included - a comment that shows the syntax as a literal example (a bare `{{ if }}` with no arguments) is invalid template code and fails to parse. Use a Go template comment instead, which is inert at render time regardless of what it contains:

```yaml
{{- /* mentioning {{ if }} in here is fine - this is a template comment, not a YAML one */ -}}
```

See [podcd's README](https://github.com/podcd/podcd#values-templating) for the full guide (opting in, merge order, available functions), and [`multi-env`](./multi-env) for a worked example across four hosts.

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

[`minimal/`](./minimal) contains a `local` host running nginx on port `8080` - the smallest complete example, one Application, one Host, no groups or environments. Point an agent at it (`--repo-path minimal`, or `path: minimal` in `agent.yaml`) and:

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
