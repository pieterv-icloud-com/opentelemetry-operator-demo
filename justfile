default:
    just --list

# Add helm repos used in this project
[group('setup')]
setup-helm:
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo add grafana-community https://grafana-community.github.io/helm-charts
    helm repo add jetstack https://charts.jetstack.io
    helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

    helm repo update

# Authenticate with GitHub CLI when no token is available
[group('setup')]
gh-auth:
    #!/usr/bin/env bash

    if ! gh auth status >/dev/null 2>&1; then
        gh auth login
        gh auth setup-git
    fi

# Generic token replacement
_replace-tokens:
    #!/usr/bin/env python3
    import os
    from pathlib import Path

    bootstrap = Path(os.environ.get("TMPDIR", "/tmp")) / "bootstrap"
    tokens = {
        name: value
        for name, value in os.environ.items()
        if name.startswith("CLUSTER_")
    }

    for path in bootstrap.rglob("*"):
        if path.is_file():
            contents = path.read_bytes()
            for name, value in tokens.items():
                contents = contents.replace(
                    f"${name}".encode(), value.encode()
                )
            path.write_bytes(contents)

_cluster-check-podman:
    #!/usr/bin/env bash
    set -euo pipefail

    : "${CONTAINER_HOST:?Set CONTAINER_HOST to the host Podman API socket}"
    if ! podman info >/dev/null; then
        echo "The host Podman service is unavailable; check its socket and the dev container's socket mount." >&2
        exit 1
    fi

_cluster-check-provider-socket:
    #!/usr/bin/env bash
    set -euo pipefail

    : "${CONTAINER_HOST:?Set CONTAINER_HOST to the host Podman API socket}"
    : "${PODMAN_HOST_SOCKET:?Set PODMAN_HOST_SOCKET to the socket path on the Podman host}"
    if [[ "$CONTAINER_HOST" != unix:///* || ! -S "${CONTAINER_HOST#unix://}" ]]; then
        echo "Podman API socket not found at $CONTAINER_HOST; start the host Podman socket and rebuild the dev container." >&2
        exit 1
    fi
    if ! podman --remote --url "$CONTAINER_HOST" info >/dev/null; then
        echo "Podman API service at $CONTAINER_HOST is not responding." >&2
        exit 1
    fi

_cluster-preflight: _cluster-check-podman _cluster-check-provider-socket


# Create the local kind cluster
[env("CLUSTER_ENVIRONMENT", "local")]
[env("CLUSTER_BRANCH", `git branch --show-current`)]
[env("CLUSTER_NAME", "opentelemetry-operator-demo")]
[env("CLOUD_PROVIDER_KIND_IMAGE", "registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.7.0")]
[group('cluster')]
cluster-create: _cluster-preflight gh-auth cluster-delete
    #!/usr/bin/env bash
    set -euo pipefail

    export CLUSTER_GITHUB_USER="$(gh api user --jq .login)"
    export CLUSTER_GITHUB_TOKEN="$(gh auth token)"
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/otel-bootstrap.XXXXXXXX")"
    trap 'rm -rf -- "$tmpdir"' EXIT

    KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --config kind-config.yaml --name "$CLUSTER_NAME"

    podman network connect kind "$(hostname)"
    KIND_EXPERIMENTAL_PROVIDER=podman kind get kubeconfig --internal --name "$CLUSTER_NAME" > "$tmpdir/kind-internal.yaml"
    kubeconfig_server="$(kubectl config view --kubeconfig "$tmpdir/kind-internal.yaml" --minify -o jsonpath='{.clusters[0].cluster.server}')"
    : "${kubeconfig_server:?Kind did not provide an internal Kubernetes API endpoint}"
    kubectl config set-cluster "kind-$CLUSTER_NAME" --server="$kubeconfig_server"

    just cluster-provider

    export TMPDIR="$tmpdir"
    mkdir -p "$tmpdir/bootstrap"
    cp -R "environments/bootstrap/$CLUSTER_ENVIRONMENT/." "$tmpdir/bootstrap/"
    just _replace-tokens

    helm install argocd --create-namespace --namespace argocd --hide-notes argo/argo-cd

    kubectl apply -k "$tmpdir/bootstrap"

# Run cloud-provider-kind for the local kind cluster
[env("CLUSTER_NAME", "opentelemetry-operator-demo")]
[env("CLOUD_PROVIDER_KIND_IMAGE", "registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.7.0")]
[group('cluster')]
cluster-provider: _cluster-check-provider-socket
    #!/usr/bin/env bash
    set -euo pipefail

    provider_container="cloud-provider-kind-${CLUSTER_NAME}"
    podman rm --force --ignore "$provider_container" >/dev/null
    podman run --detach \
        --rm \
        --name "$provider_container" \
        --network kind \
        --env KIND_EXPERIMENTAL_PROVIDER=docker \
        --env KIND_EXPERIMENTAL_DOCKER_NETWORK=kind \
        --volume "$PODMAN_HOST_SOCKET:/var/run/docker.sock" \
        "$CLOUD_PROVIDER_KIND_IMAGE" \
        --enable-lb-port-mapping

# Delete the local kind cluster
[env("CLUSTER_NAME", "opentelemetry-operator-demo")]
[group('cluster')]
cluster-delete: _cluster-check-podman
    #!/usr/bin/env bash
    set -euo pipefail

    clusters="$(KIND_EXPERIMENTAL_PROVIDER=podman kind get clusters)"

    podman rm --force --ignore "cloud-provider-kind-${CLUSTER_NAME}" >/dev/null
    podman ps -aq --filter "label=io.x-k8s.cloud-provider-kind.cluster=${CLUSTER_NAME}" | xargs -r podman rm --force >/dev/null
    podman network disconnect kind "$(hostname)" >/dev/null 2>&1 || true

    if grep -Fxq "$CLUSTER_NAME" <<< "$clusters"; then
        KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name "$CLUSTER_NAME"
    fi

# Open ArgoCD
[group('cluster')]
cluster-argocd:
    #!/usr/bin/env bash
    set -euo pipefail

    fuser -k 8082/tcp || echo "ArgoCD port wasn't open"

    export ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode)
    
    echo "Username: admin"
    echo "Password: ${ARGOCD_PASSWORD}"
    
    kubectl port-forward svc/argocd-server -n argocd 8082:443

# Open Grafana at http://localhost:3000
[group('cluster')]
cluster-grafana:
    #!/usr/bin/env bash
    set -euo pipefail

    fuser -k 3000/tcp || echo "Grafana port wasn't open"

    GRAFANA_USERNAME=$(kubectl get secret kube-prometheus-stack-grafana -n observability -o jsonpath='{.data.admin-user}' | base64 --decode)
    GRAFANA_PASSWORD=$(kubectl get secret kube-prometheus-stack-grafana -n observability -o jsonpath='{.data.admin-password}' | base64 --decode)
    
    echo "Username: ${GRAFANA_USERNAME}"
    echo "Password: ${GRAFANA_PASSWORD}"

    kubectl --namespace observability port-forward svc/kube-prometheus-stack-grafana 3000:80

# Open the Load Generator UI at http://localhost:8089
[group('cluster')]
cluster-load-generator:
    kubectl --namespace otel-demo port-forward svc/load-generator 8089:8089

# Open Jaeger at http://localhost:16686
[group('cluster')]
cluster-jaeger:
    #!/usr/bin/env bash
    set -euo pipefail

    fuser -k 16686/tcp || echo "Jaeger port wasn't open"

    kubectl --namespace observability port-forward svc/jaeger-collector 16686:16686

# Open the Flagd configurator at http://localhost:4000
[group('cluster')]
cluster-flagd-ui:
    kubectl --namespace otel-demo port-forward svc/flagd 4000:4000

# Open K9s
[group('cluster')]
cluster-k9s:
    k9s --all-namespaces    