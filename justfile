default:
    just --list

# Add helm repos used in this project
[group('setup')]
setup-helm:
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts