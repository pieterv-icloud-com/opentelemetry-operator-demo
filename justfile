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
[positional-arguments]
_replace-tokens bootstrap:
    #!/usr/bin/env python3
    import os
    import sys
    from pathlib import Path

    bootstrap = Path(sys.argv[1])
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

    : "${CONTAINER_HOST:?Host Podman socket is not configured; rebuild the dev container}"
    : "${PODMAN_HOST_SOCKET:?Host Podman socket path is not configured; rebuild the dev container}"
    if [[ "$CONTAINER_HOST" != unix:///* || ! -S "${CONTAINER_HOST#unix://}" ]]; then
        echo "Podman API socket not found at $CONTAINER_HOST; start the host Podman socket and rebuild the dev container." >&2
        exit 1
    fi
    if ! podman --remote --url "$CONTAINER_HOST" info >/dev/null; then
        echo "Podman API service at $CONTAINER_HOST is not responding." >&2
        exit 1
    fi

# Create the local kind cluster
[env("CLUSTER_ENVIRONMENT", "local")]
[env("CLUSTER_BRANCH", `git branch --show-current`)]
[env("CLUSTER_NAME", "opentelemetry-operator-demo")]
[env("CLOUD_PROVIDER_KIND_IMAGE", "registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.7.0")]
[group('cluster')]
cluster-create: _cluster-check-podman gh-auth cluster-delete
    #!/usr/bin/env bash
    set -euo pipefail

    export CLUSTER_GITHUB_USER="$(gh api user --jq .login)"
    export CLUSTER_GITHUB_TOKEN="$(gh auth token)"

    workdir="$(mktemp -d "${TMPDIR:-/tmp}/cluster-create.XXXXXXXX")"
    trap 'rm -rf "$workdir"' EXIT

    KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --config kind-config.yaml --name "$CLUSTER_NAME"

    podman network connect kind "$(hostname)"
    KIND_EXPERIMENTAL_PROVIDER=podman kind get kubeconfig --internal --name "$CLUSTER_NAME" > "$workdir/kind-internal.yaml"
    kubeconfig_server="$(kubectl config view --kubeconfig "$workdir/kind-internal.yaml" --minify -o jsonpath='{.clusters[0].cluster.server}')"
    : "${kubeconfig_server:?Kind did not provide an internal Kubernetes API endpoint}"
    kubectl config set-cluster "kind-$CLUSTER_NAME" --server="$kubeconfig_server"

    just cluster-provider

    mkdir -p "$workdir/bootstrap"
    cp -R "environments/bootstrap/$CLUSTER_ENVIRONMENT/." "$workdir/bootstrap/"
    just _replace-tokens "$workdir/bootstrap"

    helm install argocd --create-namespace --namespace argocd --hide-notes --wait=watcher --wait-for-jobs -f argocd-values.yaml argo/argo-cd

    kubectl apply -k "$workdir/bootstrap"

# Run cloud-provider-kind for the local kind cluster
[env("CLUSTER_NAME", "opentelemetry-operator-demo")]
[env("CLOUD_PROVIDER_KIND_IMAGE", "registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.7.0")]
[group('cluster')]
cluster-provider: _cluster-check-podman
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
    echo "URL: http://localhost:8082"

    # kubectl port-forward exits when the tunnel to the pod drops; reconnect instead of failing.
    while true; do
        kubectl port-forward svc/argocd-server -n argocd 8082:80 || true
        echo "Port-forward dropped, reconnecting in 2s..."
        sleep 2
    done

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