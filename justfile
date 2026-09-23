default:
    just --list

# Add helm repos used in this project
[group('setup')]
setup-helm:
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts

# Create the local kind cluster
[group('cluster')]
cluster-create:
    kind create cluster --config kind-config.yaml

# Delete the local kind cluster
[group('cluster')]
cluster-delete:
    kind delete cluster --name opentelemetry-operator-demo