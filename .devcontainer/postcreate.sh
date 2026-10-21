#!/usr/bin/env zsh
set -euo pipefail

secretspec config global init --provider keyring --profile default

just setup-helm