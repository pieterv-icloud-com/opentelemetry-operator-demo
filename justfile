default:
    just --list

# Add helm repos used in this project
[group('setup')]
setup-helm:
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts

    helm repo update

# Authenticate with GitHub CLI when no token is available
[group('setup')]
gh-auth:
    #!/usr/bin/env bash

    if ! gh auth status >/dev/null 2>&1; then
        gh auth login
        gh auth setup-git
    fi

# Create the local kind cluster
[env("CLUSTER_ENVIRONMENT", "local")]
[env("CLUSTER_BRANCH", `git branch --show-current`)]
[env("CLUSTER_NAME", "opentelemetry-operator-demo")]
[group('cluster')]
cluster-create: gh-auth cluster-delete
    #!/usr/bin/env bash

    export CLUSTER_GITHUB_USER="$(gh api user --jq .login)"
    export CLUSTER_GITHUB_TOKEN="$(gh auth token)"

    kind create cluster --config kind-config.yaml --name $CLUSTER_NAME

# Delete the local kind cluster
[env("CLUSTER_NAME", "opentelemetry-operator-demo")]
[group('cluster')]
cluster-delete:
    #!/usr/bin/env bash

    if kind get clusters | grep -Fxq "$CLUSTER_NAME"; then
        kind delete cluster --name "$CLUSTER_NAME"
    fi