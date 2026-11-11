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


# Create the local kind cluster
[env("CLUSTER_ENVIRONMENT", "local")]
[env("CLUSTER_BRANCH", `git branch --show-current`)]
[env("CLUSTER_NAME", "opentelemetry-operator-demo")]
[env("CLOUD_PROVIDER_KIND_IMAGE", "registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.7.0")]
[group('cluster')]
cluster-create: gh-auth cluster-delete
    #!/usr/bin/env bash
    set -euo pipefail

    export CLUSTER_GITHUB_USER="$(gh api user --jq .login)"
    export CLUSTER_GITHUB_TOKEN="$(gh auth token)"

    workdir="$(mktemp -d "${TMPDIR:-/tmp}/cluster-create.XXXXXXXX")"
    trap 'rm -rf "$workdir"' EXIT

    gateway="$(ip -4 route show default | awk '$1 == "default" && $2 == "via" {print $3; exit}')"
    if [[ -z "$gateway" ]]; then
        echo "Cannot determine the container's default IPv4 gateway" >&2
        exit 1
    fi

    python3 - "$gateway" "$workdir/kind-config.yaml" <<'PY'
    import ipaddress
    import sys
    from pathlib import Path

    gateway = str(ipaddress.IPv4Address(sys.argv[1]))
    config = Path("kind-config.yaml").read_text()
    placeholder = "KIND_API_SERVER_GATEWAY"
    if config.count(placeholder) != 1:
        sys.exit("kind-config.yaml must contain exactly one API server gateway placeholder")
    Path(sys.argv[2]).write_text(config.replace(placeholder, gateway))
    PY

    kind create cluster --config "$workdir/kind-config.yaml" --name "$CLUSTER_NAME"

    just cluster-provider

    # Use the same gateway in kubeconfig and the API server certificate.
    kubeconfig_server="$(kubectl config view --context "kind-$CLUSTER_NAME" --minify -o jsonpath='{.clusters[0].cluster.server}')"
    if [[ "$kubeconfig_server" != https://0.0.0.0:* ]]; then
        echo "Unexpected kind API server URL: $kubeconfig_server" >&2
        exit 1
    fi
    kubectl config set-cluster "kind-$CLUSTER_NAME" \
        --server="${kubeconfig_server/0.0.0.0/$gateway}"

    # Kind forwards CoreDNS to the node's resolv.conf, which fails for pods in this devcontainer.
    coredns_corefile="$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')"
    if [[ "$coredns_corefile" != *"forward . /etc/resolv.conf"* ]]; then
        echo "Unexpected CoreDNS forward configuration; not patching" >&2
        exit 1
    fi
    kubectl -n kube-system get configmap coredns -o yaml \
        | sed 's|forward \. /etc/resolv\.conf|forward . 8.8.8.8 1.1.1.1|' \
        | kubectl replace -f -
    kubectl -n kube-system rollout restart deployment coredns
    kubectl -n kube-system rollout status deployment coredns --timeout=180s

    # Attach this devcontainer to the kind network so LoadBalancer IPs are reachable directly.
    podman network connect kind "$(hostname)" >/dev/null 2>&1 || true

    mkdir -p "$workdir/bootstrap"
    cp -R "environments/bootstrap/$CLUSTER_ENVIRONMENT/." "$workdir/bootstrap/"
    just _replace-tokens "$workdir/bootstrap"

    helm install argocd --create-namespace --namespace argocd --hide-notes argo/argo-cd

    kubectl apply -k "$workdir/bootstrap"

# Run cloud-provider-kind for the local kind cluster
[env("CLUSTER_NAME", "opentelemetry-operator-demo")]
[env("CLOUD_PROVIDER_KIND_IMAGE", "registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.7.0")]
[group('cluster')]
cluster-provider:
    #!/usr/bin/env bash
    set -euo pipefail

    provider_container="cloud-provider-kind-${CLUSTER_NAME}"
    podman rm --force "$provider_container" >/dev/null 2>&1 || true
    podman run --detach \
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

    podman rm --force "cloud-provider-kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
    podman ps -aq --filter "label=io.x-k8s.cloud-provider-kind.cluster=${CLUSTER_NAME}" | xargs -r podman rm --force >/dev/null
    podman network disconnect kind "$(hostname)" >/dev/null 2>&1 || true

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