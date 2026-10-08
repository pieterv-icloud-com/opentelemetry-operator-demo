# OpenTelemetry Operator Demo

A local Kubernetes demo environment for exploring the OpenTelemetry Operator and
the OpenTelemetry Demo application. The cluster and its add-ons are managed with
`kind`, Argo CD, Helm, and Kustomize. The observability stack includes
Prometheus/Grafana, Loki, Tempo, Pyroscope, and Jaeger.

## Getting started

Open this repository in VS Code and choose **Reopen in Container**. The
Dev Container installs the project tools and forwards the local UI ports.

Project tasks are available both as `just` recipes and as VS Code tasks. Run
them from the terminal with `just <task-name>`, or choose **Terminal > Run
Task** in VS Code. The `cluster-create` task runs `gh-auth`; if GitHub CLI
(`gh`) is not already authenticated, it starts `gh auth login` and configures
Git access. Cluster bootstrap uses the authenticated GitHub username and token
to create Argo CD repository credentials; do not add a token to repository
files.

Create the local cluster and bootstrap Argo CD by running `cluster-create`:

```sh
just cluster-create
```

Argo CD then deploys the applications defined under `environments/`. Its Git
source tracks the current branch by default (`CLUSTER_BRANCH`), so that branch
must be available in the configured Git remote for Argo CD to sync it.

> **Warning:** `cluster-create` runs `cluster-delete` first. It deletes an
> existing `kind` cluster with the configured name before creating it again.
> Kubernetes resources and data in that cluster will be lost.

## Project tasks

Each task is available as both a `just` recipe and a VS Code task. VS Code task
labels match the names below; to list recipes in the terminal, run `just
--list`.

| Task | Description |
| --- | --- |
| `gh-auth` | Check GitHub CLI authentication; start login and set up Git authentication if needed. |
| `cluster-create` | Recreate the `kind` cluster, start `cloud-provider-kind`, install Argo CD, and apply the bootstrap manifests. |
| `cluster-delete` | Stop the local cloud provider and delete the configured `kind` cluster. |
| `cluster-provider` | Start `cloud-provider-kind` for the configured cluster. |
| `cluster-argocd` | Print the initial Argo CD admin credentials and port-forward its UI to <https://localhost:8082>. |
| `cluster-grafana` | Print the Grafana credentials and port-forward Grafana to <http://localhost:3000>. |
| `cluster-jaeger` | Port-forward Jaeger to <http://localhost:16686>. |
| `cluster-load-generator` | Port-forward the OpenTelemetry Demo load generator to <http://localhost:8089>. |
| `cluster-flagd-ui` | Port-forward the feature-flag configurator to <http://localhost:4000>. |
| `cluster-k9s` | Open K9s for all namespaces. |

The port-forward recipes run in the foreground; leave their terminal sessions
running while using the corresponding UI. Stop a port-forward with `Ctrl+C`.

## Repository layout

- `environments/bootstrap/` — Argo CD configuration, project, repository
  credentials, and applications.
- `environments/overlays/` — Helm-backed infrastructure and demo applications.
- `environments/annotations/` — OpenTelemetry Collector configuration,
  permissions, Jaeger configuration, and Grafana dashboards.
- `kind-config.yaml` — Local Kubernetes cluster configuration.
- `justfile` — Setup, cluster lifecycle, and port-forward recipes.
- `.devcontainer/` — VS Code Dev Container tooling and initialization.
- `.vscode/tasks.json` — VS Code tasks for the `just` recipes.

## Cleaning up

Delete the local cluster when finished:

```sh
just cluster-delete
```
