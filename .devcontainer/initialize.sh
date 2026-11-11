#!/bin/bash
# Initialize script for devcontainer - runs on HOST before container starts
# Cleans up stale devcontainer containers that may cause issues

set -e

echo "Initializing devcontainer environment..."

# Get container name/ID for this workspace to clean up its specific temp dirs
WORKSPACE_NAME=$(basename "$(pwd)")

# Check if we're using Podman (either directly or as docker alias)
is_podman() {
    if command -v podman &> /dev/null; then
        # Check if docker is actually podman (common alias setup)
        if command -v docker &> /dev/null; then
            docker --version 2>/dev/null | grep -qi "podman" && return 0
        fi
        # Also check if podman is available and docker isn't real docker
        return 0
    fi
    return 1
}

# Configure Podman for rootless builds - fixes /tmp permission issues
configure_podman() {
    local config_dir="$HOME/.config/containers"
    local containers_conf="$config_dir/containers.conf"
    
    mkdir -p "$config_dir"
    
    # Check if already fully configured
    if [[ -f "$containers_conf" ]] && grep -q 'TMPDIR=/var/tmp' "$containers_conf" 2>/dev/null; then
        echo "Podman TMPDIR already configured."
        return 0
    fi
    
    echo "Configuring Podman for rootless builds..."
    
    # We need to set TMPDIR in multiple places:
    # 1. [engine] env - for podman's own processes
    # 2. [containers] env - for default container environment (affects builds)
    
    if [[ -f "$containers_conf" ]]; then
        # Backup existing config
        cp "$containers_conf" "${containers_conf}.bak"
        
        # Add [engine] env if not present
        if grep -q '^\[engine\]' "$containers_conf"; then
            if ! grep -q 'env.*TMPDIR' "$containers_conf"; then
                sed -i '/^\[engine\]/a env = ["TMPDIR=/var/tmp"]' "$containers_conf"
            fi
        else
            echo -e "\n[engine]\nenv = [\"TMPDIR=/var/tmp\"]" >> "$containers_conf"
        fi
        
        # Add [containers] env if not present - this sets default env for containers
        if grep -q '^\[containers\]' "$containers_conf"; then
            if ! grep -A5 '^\[containers\]' "$containers_conf" | grep -q 'env.*TMPDIR'; then
                sed -i '/^\[containers\]/a env = ["TMPDIR=/var/tmp"]' "$containers_conf"
            fi
        else
            echo -e "\n[containers]\nenv = [\"TMPDIR=/var/tmp\"]" >> "$containers_conf"
        fi
    else
        # Create new config file with both sections
        cat > "$containers_conf" << 'EOF'
[containers]
env = ["TMPDIR=/var/tmp"]

[engine]
env = ["TMPDIR=/var/tmp"]
EOF
    fi
    
    echo "Podman configured to use /var/tmp for temp files."
}

# Run Podman configuration if needed
if is_podman; then
    configure_podman
fi

echo "Initialization complete."