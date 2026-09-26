default:
    just --list

# Add helm repos used in this project
[group('setup')]
setup-helm:
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo add jetstack https://charts.jetstack.io
    helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server
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


# Create the local kind cluster
[env("CLUSTER_ENVIRONMENT", "local")]
[env("CLUSTER_BRANCH", `git branch --show-current`)]
[env("CLUSTER_NAME", "opentelemetry-operator-demo")]
[env("CLOUD_PROVIDER_KIND_IMAGE", "registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.7.0")]
[group('cluster')]
cluster-create: gh-auth cluster-delete
    #!/usr/bin/env bash

    export CLUSTER_GITHUB_USER="$(gh api user --jq .login)"
    export CLUSTER_GITHUB_TOKEN="$(gh auth token)"
    tmpdir="${TMPDIR:-/tmp}"

    kind create cluster --config kind-config.yaml --name $CLUSTER_NAME

    just cluster-provider

    # Kind writes 0.0.0.0 to kubeconfig; use the Docker gateway from this container.
    kubeconfig_server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
    docker_gateway="$(ip route | awk '$1 == "default" {print $3; exit}')"
    kubectl config set-cluster "kind-$CLUSTER_NAME" \
        --server="${kubeconfig_server/0.0.0.0/$docker_gateway}"

    # Attach this devcontainer to the kind network so LoadBalancer IPs are reachable directly.
    docker network connect kind "$(hostname)" >/dev/null 2>&1 || true

    mkdir -p "$tmpdir/bootstrap"
    cp -R "environments/bootstrap/$CLUSTER_ENVIRONMENT/." "$tmpdir/bootstrap/"
    just _replace-tokens

    helm install argocd --create-namespace --namespace argocd --hide-notes argo/argo-cd

    kubectl apply -k $tmpdir/bootstrap

    rm -rf "$tmpdir/bootstrap"

# Run cloud-provider-kind for the local kind cluster
[env("CLUSTER_NAME", "opentelemetry-operator-demo")]
[env("CLOUD_PROVIDER_KIND_IMAGE", "registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.7.0")]
[group('cluster')]
cluster-provider:
    #!/usr/bin/env bash
    set -euo pipefail

    provider_container="cloud-provider-kind-${CLUSTER_NAME}"
    docker rm --force "$provider_container" >/dev/null 2>&1 || true
    docker run --detach \
        --rm \
        --name "$provider_container" \
        --network kind \
        --env KIND_EXPERIMENTAL_PROVIDER=docker \
        --env KIND_EXPERIMENTAL_DOCKER_NETWORK=kind \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        "$CLOUD_PROVIDER_KIND_IMAGE" \
        --enable-lb-port-mapping

# Delete the local kind cluster
[env("CLUSTER_NAME", "opentelemetry-operator-demo")]
[group('cluster')]
cluster-delete:
    #!/usr/bin/env bash

    docker rm --force "cloud-provider-kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
    docker ps -aq --filter "label=io.x-k8s.cloud-provider-kind.cluster=${CLUSTER_NAME}" | xargs -r docker rm --force >/dev/null
    docker network disconnect kind "$(hostname)" >/dev/null 2>&1 || true

    if kind get clusters | grep -Fxq "$CLUSTER_NAME"; then
        kind delete cluster --name "$CLUSTER_NAME"
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
    kubectl --namespace otel-demo port-forward svc/grafana 3000:80

# Open the Load Generator UI at http://localhost:8089
[group('cluster')]
cluster-load-generator:
    kubectl --namespace otel-demo port-forward svc/load-generator 8089:8089

# Open Jaeger at http://localhost:16686
[group('cluster')]
cluster-jaeger:
    kubectl --namespace otel-demo port-forward svc/jaeger 16686:16686

# Open the Flagd configurator at http://localhost:4000
[group('cluster')]
cluster-flagd-ui:
    kubectl --namespace otel-demo port-forward svc/flagd 4000:4000

# Open K9s
[group('cluster')]
cluster-k9s:
    k9s --all-namespaces    