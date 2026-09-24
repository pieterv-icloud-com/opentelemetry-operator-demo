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
[group('cluster')]
cluster-create: gh-auth cluster-delete
    #!/usr/bin/env bash

    export CLUSTER_GITHUB_USER="$(gh api user --jq .login)"
    export CLUSTER_GITHUB_TOKEN="$(gh auth token)"
    tmpdir="${TMPDIR:-/tmp}"

    kind create cluster --config kind-config.yaml --name $CLUSTER_NAME

    # Kind writes 0.0.0.0 to kubeconfig; use the Docker gateway from this container.
    kubeconfig_server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
    docker_gateway="$(ip route | awk '$1 == "default" {print $3; exit}')"
    kubectl config set-cluster "kind-$CLUSTER_NAME" \
        --server="${kubeconfig_server/0.0.0.0/$docker_gateway}"

    mkdir -p "$tmpdir/bootstrap"
    cp -R "environments/bootstrap/$CLUSTER_ENVIRONMENT/." "$tmpdir/bootstrap/"
    just _replace-tokens

    helm install argocd --create-namespace --namespace argocd --hide-notes argo/argo-cd

    kubectl apply -k $tmpdir/bootstrap

    rm -rf "$tmpdir/bootstrap"

# Delete the local kind cluster
[env("CLUSTER_NAME", "opentelemetry-operator-demo")]
[group('cluster')]
cluster-delete:
    #!/usr/bin/env bash

    if kind get clusters | grep -Fxq "$CLUSTER_NAME"; then
        kind delete cluster --name "$CLUSTER_NAME"
    fi

# Open ArgoCD
[group('cluster')]
cluster-argocd:
    #!/usr/bin/env bash
    set -euo pipefail

    fuser -k 8080/tcp || echo "ArgoCD port wasn't open"

    export ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode)
    
    echo "Username: admin"
    echo "Password: ${ARGOCD_PASSWORD}"
    
    kubectl port-forward svc/argocd-server -n argocd 8080:443    

# Open K9s
[group('cluster')]
cluster-k9s:
    k9s --all-namespaces    