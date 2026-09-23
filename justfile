default:
    just --list

[group('setup')]
setup-helm:
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts