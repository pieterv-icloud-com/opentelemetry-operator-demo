default:
    just --list

# Add helm repos used in this project
[group('setup')]
setup-helm:
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts

# Authenticate with GitHub CLI when no token is available
[group('setup')]
gh-auth:
    gh auth token >/dev/null 2>&1 || gh auth login

# Create the local kind cluster
[group('cluster')]
cluster-create:
    kind create cluster --config kind-config.yaml

# Delete the local kind cluster
[group('cluster')]
cluster-delete:
    kind delete cluster --name opentelemetry-operator-demo
