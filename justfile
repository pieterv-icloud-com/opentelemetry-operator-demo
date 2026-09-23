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
    gh auth token >/dev/null 2>&1 || gh auth login || gh auth setup-git
# Create the local kind cluster
[env("ENVIRONMENT", "local")]
[env("BRANCH", `git branch --show-current`)]
[env("CLUSTER_NAME", "opentelemetry-operator-demo")]
[group('cluster')]
cluster-create: gh-auth
    #!/usr/bin/env bash

    export GITHUB_USER="$(gh api user --jq .login)"
    export GITHUB_TOKEN="$(gh auth token)"

    if kind get clusters | grep -Fxq "$CLUSTER_NAME"; then
        kind delete cluster --name "$CLUSTER_NAME"
    fi

    kind create cluster --config kind-config.yaml --name $CLUSTER_NAME

# Delete the local kind cluster
[group('cluster')]
cluster-delete:
    kind delete cluster --name "$CLUSTER_NAME"
