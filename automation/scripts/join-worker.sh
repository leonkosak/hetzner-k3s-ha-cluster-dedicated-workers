#!/usr/bin/env bash
set -euo pipefail

# Required env vars:
#   K3S_URL=https://k8s-api.example.com:6443
#   K3S_TOKEN=<cluster-node-token>
# Optional:
#   INSTALL_K3S_VERSION=v1.32.3+k3s1
#   NODE_LABELS="--node-label nodepool=gpu --node-label accelerator=nvidia"
#   NODE_TAINTS="--node-taint nvidia.com/gpu=true:NoSchedule"

: "${K3S_URL:?K3S_URL is required}"
: "${K3S_TOKEN:?K3S_TOKEN is required}"

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${INSTALL_K3S_VERSION:-}" \
  K3S_URL="$K3S_URL" \
  K3S_TOKEN="$K3S_TOKEN" \
  sh -s - agent ${NODE_LABELS:-} ${NODE_TAINTS:-}
