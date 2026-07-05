#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   INSTALL_K3S_VERSION=v1.32.3+k3s1

: "${INSTALL_K3S_VERSION:?INSTALL_K3S_VERSION is required}"

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$INSTALL_K3S_VERSION" sh -
