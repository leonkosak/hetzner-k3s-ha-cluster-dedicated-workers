#!/usr/bin/env bash
################################################################################
# deploy-rancher.sh — Install Rancher for K3s cluster management
#
# Deploys cert-manager + Rancher with a Traefik IngressRoute and Let's Encrypt.
# Accessible at https://rancher.<master-ip>.nip.io
#
# Usage:
#   source hcloud_server_ips.env
#   ./deploy-rancher.sh
#
# Env vars:
#   RANCHER_HOST       Override hostname (default: rancher.<MASTER_IP>.nip.io)
#   RANCHER_VERSION     Rancher Helm chart version (default: latest stable)
#   RANCHER_PASSWORD    Initial admin password (default: auto-generated)
################################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- config -----------------------------------------------------------
if [[ -f "$SCRIPT_DIR/hcloud_server_ips.env" ]]; then
  source "$SCRIPT_DIR/hcloud_server_ips.env"
fi

MASTER_IP="${MASTER_IP:-${IP_MASTER_1:-}}"
RANCHER_NAMESPACE="${RANCHER_NAMESPACE:-cattle-system}"
RANCHER_HOST="${RANCHER_HOST:-rancher.${MASTER_IP}.nip.io}"
RANCHER_VERSION="${RANCHER_VERSION:-2.14.3}"
RANCHER_PASSWORD="${RANCHER_PASSWORD:-admin}"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# ----------------------------------------------------------------------

SSH_KEY_CANDIDATES=()
[[ -n "${SSH_KEY:-}" ]] && SSH_KEY_CANDIDATES+=("$SSH_KEY")
SSH_KEY_CANDIDATES+=("$HOME/.ssh/id_rsa" "/home/pesto/.ssh/id_rsa")

SSH_KEY=""
for c in "${SSH_KEY_CANDIDATES[@]}"; do
  [[ -n "$c" && -f "$c" ]] && { SSH_KEY="$c"; break; }
done

if [[ -z "$SSH_KEY" ]]; then
  echo "No SSH key found. Set SSH_KEY or MASTER_SSH_KEY." >&2; exit 1
fi

if [[ -z "$MASTER_IP" ]]; then
  echo "MASTER_IP not set. Source hcloud_server_ips.env first." >&2; exit 1
fi

TMP_KUBECONFIG="$(mktemp)"
trap 'rm -f "$TMP_KUBECONFIG"' EXIT

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "root@$MASTER_IP" 'cat /etc/rancher/k3s/k3s.yaml' \
  | sed "s#https://127.0.0.1:6443#https://$MASTER_IP:6443#g" > "$TMP_KUBECONFIG"

K=(kubectl --kubeconfig="$TMP_KUBECONFIG")

echo "=== Installing cert-manager ==="
"${K[@]}" apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml
"${K[@]}" -n cert-manager rollout status deployment/cert-manager --timeout=180s
"${K[@]}" -n cert-manager rollout status deployment/cert-manager-webhook --timeout=180s
echo "cert-manager ready."

echo "=== Adding Rancher Helm repo ==="
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest 2>/dev/null || true
helm repo update

echo "=== Installing Rancher $RANCHER_VERSION ==="
"${K[@]}" create namespace "$RANCHER_NAMESPACE" --dry-run=client -o yaml | "${K[@]}" apply -f -

helm upgrade --install rancher rancher-latest/rancher \
  --namespace "$RANCHER_NAMESPACE" \
  --version "$RANCHER_VERSION" \
  --set hostname="$RANCHER_HOST" \
  --set bootstrapPassword="$RANCHER_PASSWORD" \
  --set replicas=1 \
  --set ingress.enabled=false \
  --wait --timeout 10m

echo "=== Creating Traefik IngressRoute for Rancher ==="
"${K[@]}" -n "$RANCHER_NAMESPACE" apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: rancher
  namespace: $RANCHER_NAMESPACE
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`${RANCHER_HOST}\`)
      kind: Rule
      services:
        - name: rancher
          port: 80
  tls:
    certResolver: le
EOF

echo ""
echo "=============================================="
echo "  Rancher deployed!"
echo "  URL:      https://${RANCHER_HOST}"
echo "  Username: admin"
echo "  Password: ${RANCHER_PASSWORD}"
echo "=============================================="
echo ""
echo "Wait 2-3 min for Rancher to fully initialize, then log in."
echo "After login, go to ☰ → Cluster Management → Import Existing"
echo "to add this K3s cluster."
