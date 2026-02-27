#!/usr/bin/env bash
set -euo pipefail

# For first server (cluster-init):
#   export K3S_MODE=init
# For joining servers:
#   export K3S_MODE=join
#   export K3S_URL=https://k8s-api.example.com:6443
#   export K3S_TOKEN=<cluster-node-token>
# Required for both:
#   export K3S_API_ENDPOINT=k8s-api.example.com

: "${K3S_MODE:?K3S_MODE is required (init|join)}"
: "${K3S_API_ENDPOINT:?K3S_API_ENDPOINT is required}"

if [[ "$K3S_MODE" == "init" ]]; then
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="${INSTALL_K3S_VERSION:-}" \
    sh -s - server --cluster-init --tls-san "$K3S_API_ENDPOINT"
elif [[ "$K3S_MODE" == "join" ]]; then
  : "${K3S_URL:?K3S_URL is required for join}"
  : "${K3S_TOKEN:?K3S_TOKEN is required for join}"
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="${INSTALL_K3S_VERSION:-}" \
    K3S_URL="$K3S_URL" \
    K3S_TOKEN="$K3S_TOKEN" \
    sh -s - server --tls-san "$K3S_API_ENDPOINT"
else
  echo "Unsupported K3S_MODE: $K3S_MODE"
  exit 1
fi
