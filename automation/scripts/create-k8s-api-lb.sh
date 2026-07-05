#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- config -----------------------------------------------------------
CLUSTER_TAG="${CLUSTER_TAG:-k3s-cluster}"
LB_NAME="${LB_NAME:-${CLUSTER_TAG}-api-lb}"
LB_TYPE="${LB_TYPE:-lb11}"
LB_LOCATION="${LB_LOCATION:-nbg1}"
LB_PORT="${LB_PORT:-6443}"
PERMANENT=false
DELETE=false
KUBECONFIG_DEST="${KUBECONFIG_DEST:-$HOME/.kube/config}"
MASTER_SSH_KEY="${MASTER_SSH_KEY:-$HOME/.ssh/id_rsa}"
# ----------------------------------------------------------------------

usage() {
  echo "Usage: $0 [--permanent] [--delete]"
  echo ""
  echo "Options:"
  echo "  --permanent  Create LB and save kubeconfig to ${KUBECONFIG_DEST}"
  echo "               pointing at the LB IP (requires SSH to first master)"
  echo "  --delete     Remove the load balancer and its targets from Hetzner"
  echo "  -h, --help   Show this help"
  echo ""
  echo "Environment:"
  echo "  KUBECONFIG_DEST   Where to save kubeconfig (default: ~/.kube/config)"
  echo "  MASTER_SSH_KEY    SSH private key path (default: ~/.ssh/id_rsa)"
  echo "  LB_NAME           Override LB name (default: k3s-cluster-api-lb)"
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --permanent) PERMANENT=true ;;
    --delete)    DELETE=true ;;
    -h|--help)   usage ;;
    *)           echo "Unknown option: $arg"; usage ;;
  esac
done

if [[ -f "$SCRIPT_DIR/hcloud-config.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/hcloud-config.env"
fi

# Auto-detect HCLOUD_TOKEN
if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
  for src in "$HOME/.config/hetzner/runtime.env" "$SCRIPT_DIR/../.env"; do
    if [[ -f "$src" ]]; then source "$src" 2>/dev/null || true; break; fi
  done
fi
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN is required. Source ~/.config/hetzner/runtime.env or export it.}"

# --- delete ------------------------------------------------------------
if [[ "$DELETE" == "true" ]]; then
  if hcloud load-balancer list --output json 2>/dev/null | python3 -c "import sys,json; any(l['name']=='$LB_NAME' for l in json.load(sys.stdin)) and sys.exit(0) or sys.exit(1)" 2>/dev/null; then
    echo "Removing load balancer '$LB_NAME'..."
    hcloud load-balancer delete "$LB_NAME"
    echo "Done."
  else
    echo "Load balancer '$LB_NAME' not found — nothing to delete."
  fi
  exit 0
fi

if [[ -f "$SCRIPT_DIR/hcloud_server_ips.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/hcloud_server_ips.env"
fi

: "${HCLOUD_TOKEN:?HCLOUD_TOKEN is required. Source ~/.config/hetzner/runtime.env or set it.}"
: "${MASTER_COUNT:?MASTER_COUNT is required. Source hcloud_server_ips.env.}"
: "${IP_MASTER_1:?IP_MASTER_1 is required. Source hcloud_server_ips.env.}"

# --- check if LB already exists ----------------------------------------
if EXISTING_LB_ID=$(hcloud load-balancer list --output json 2>/dev/null | \
  python3 -c "import sys,json; lbs=[l for l in json.load(sys.stdin) if l['name']=='$LB_NAME']; print(lbs[0]['id'] if lbs else '')" 2>/dev/null); then
  if [[ -n "$EXISTING_LB_ID" ]]; then
    EXISTING_LB_IP=$(hcloud load-balancer describe "$LB_NAME" --output json 2>/dev/null | \
      python3 -c "import sys,json; d=json.load(sys.stdin); print(d['public_net']['ipv4']['ip'])")
    echo "Load balancer '$LB_NAME' already exists ($EXISTING_LB_IP)."

    # Refresh targets — remove old, attach current masters
    echo "Refreshing targets..."
    for i in $(seq 1 "$MASTER_COUNT"); do
      SERVER_NAME="k3s-master-$i"
      hcloud load-balancer remove-target "$LB_NAME" --server "$SERVER_NAME" 2>/dev/null || true
      hcloud load-balancer add-target "$LB_NAME" --server "$SERVER_NAME"
      echo "  -> $SERVER_NAME"
    done
    LB_IP="$EXISTING_LB_IP"
  fi
else
  # --- create load balancer --------------------------------------------
  echo "Creating load balancer '$LB_NAME' ($LB_TYPE) in $LB_LOCATION..."
  LB_ID=$(hcloud load-balancer create --name "$LB_NAME" --type "$LB_TYPE" --location "$LB_LOCATION" \
    --output json | python3 -c "import sys,json; print(json.load(sys.stdin)['load_balancer']['id'])")

  echo "Adding API service on port $LB_PORT..."
  hcloud load-balancer add-service "$LB_NAME" \
    --protocol tcp \
    --listen-port "$LB_PORT" \
    --destination-port "$LB_PORT" \
    >/dev/null

  # --- attach all master nodes as targets ------------------------------
  echo "Attaching master nodes as targets..."
  for i in $(seq 1 "$MASTER_COUNT"); do
    SERVER_NAME="k3s-master-$i"
    echo "  -> $SERVER_NAME"
    hcloud load-balancer add-target "$LB_NAME" --server "$SERVER_NAME"
  done

  LB_IP=$(hcloud load-balancer describe "$LB_NAME" --output json | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d['public_net']['ipv4']['ip'])")
fi

# --- output ------------------------------------------------------------
echo ""
echo "=========================================="
echo "  K8s API Load Balancer"
echo "  IP:   $LB_IP"
echo "  Port: $LB_PORT"
echo "=========================================="
echo ""

# --- optional: save permanent kubeconfig -------------------------------
if [[ "$PERMANENT" == "true" ]]; then
  # If KUBECONFIG is already set, use that file instead
  if [[ -n "${KUBECONFIG:-}" ]] && [[ "$KUBECONFIG" != "$KUBECONFIG_DEST" ]]; then
    echo "KUBECONFIG is set to $KUBECONFIG — saving there instead."
    KUBECONFIG_DEST="$KUBECONFIG"
  fi
  mkdir -p "$(dirname "$KUBECONFIG_DEST")"
  echo "Saving kubeconfig to $KUBECONFIG_DEST ..."
  ssh -i "$MASTER_SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "root@$IP_MASTER_1" 'cat /etc/rancher/k3s/k3s.yaml' \
    | sed -E "s#https://(127\.0\.0\.1|${IP_MASTER_1//./\\.}):6443#https://$LB_IP:$LB_PORT#g" \
    | python3 -c "
import sys, yaml
k = yaml.safe_load(sys.stdin)
k['clusters'][0]['cluster']['insecure-skip-tls-verify'] = True
k['clusters'][0]['cluster'].pop('certificate-authority-data', None)
yaml.dump(k, sys.stdout, default_flow_style=False)
" \
    > "$KUBECONFIG_DEST"
  chmod 600 "$KUBECONFIG_DEST"
  echo "Done. Run: kubectl get nodes"
  echo ""
  echo "Note: TLS verification is disabled in the saved kubeconfig because the"
  echo "LB IP is not in the K3s certificate. When recreating the cluster, the"
  echo "Ansible playbook will auto-detect the LB and add it as a tls-san."
else
  echo "Use the LB with kubectl:"
  echo "  kubectl --kubeconfig=<(ssh root@$IP_MASTER_1 'cat /etc/rancher/k3s/k3s.yaml' \\"
  echo "    | sed 's#https://127.0.0.1:6443#https://$LB_IP:$LB_PORT#g') get nodes"
  echo ""
  echo "Or save permanently:"
  echo "  ./create-k8s-api-lb.sh --permanent"
fi
