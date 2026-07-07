#!/usr/bin/env bash
################################################################################
# create-cluster.sh — End-to-end K3s HA cluster on Hetzner Cloud
#
# Runs every step in sequence:
#   1. Create Hetzner servers (masters + workers)
#   2. Create K3s API Load Balancer (if CREATE_LB=1)
#   3. Wait for SSH, then bootstrap OS via Ansible
#   4. Install K3s servers (auto-detects LB IP for TLS cert)
#   5. Install K3s agents
#   6. Configure Let's Encrypt on Traefik
#   7. Deploy Rancher (if INSTALL_RANCHER=1)
#   8. Save kubeconfig with LB IP
#
# Usage:
#   1. Copy hcloud-config.env.example to hcloud-config.env and edit it
#   2. export HCLOUD_TOKEN="..."  (or source ~/.config/hetzner/runtime.env)
#   3. ./create-cluster.sh
#
# Optional env vars override hcloud-config.env settings:
#   CREATE_LB=1|0             Create API load balancer (default: 0)
#   INSTALL_RANCHER=1|0       Deploy Rancher for cluster management (default: 0)
#   RANCHER_PASSWORD          Initial admin password (default: admin123)
################################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ANSIBLE_DIR="$REPO_ROOT/automation/ansible"

# --- config -----------------------------------------------------------
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/hcloud-config.env}"
# ----------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
ok()    { echo -e "${GREEN}[$(date +%H:%M:%S)] ✓${NC} $*"; }
warn()  { echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠${NC} $*"; }
err()   { echo -e "${RED}[$(date +%H:%M:%S)] ✗${NC} $*"; }

# --- load config -------------------------------------------------------
if [[ -f "$CONFIG_FILE" ]]; then
  log "Loading configuration from $CONFIG_FILE"
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

# defaults
CREATE_LB="${CREATE_LB:-0}"
INSTALL_RANCHER="${INSTALL_RANCHER:-0}"
RANCHER_PASSWORD="${RANCHER_PASSWORD:-admin123}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}"
ANSIBLE_INVENTORY="$SCRIPT_DIR/hcloud_servers_inventory.yml"

# Auto-detect HCLOUD_TOKEN from common locations.
# To create a token: https://console.hetzner.com/ → your project → Security → API Tokens
# Then store it: echo 'export HCLOUD_TOKEN="..."' > ~/.config/hetzner/runtime.env
# See 00_START_HERE.md for overview and 01_QUICKSTART.md for step-by-step instructions.
if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
  for src in "$HOME/.config/hetzner/runtime.env" "$SCRIPT_DIR/../.env"; do
    if [[ -f "$src" ]]; then
      source "$src" 2>/dev/null || true
      break
    fi
  done
fi
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN is required. Source ~/.config/hetzner/runtime.env or export it.}"

###############################################################################
# STEP 1: Create servers
###############################################################################
log "=========================================="
log "STEP 1: Creating Hetzner servers"
log "=========================================="
cd "$SCRIPT_DIR"

# Fix inventory SSH key path before running Ansible
fix_inventory_key() {
  sed -i "s#ansible_ssh_private_key_file:.*#ansible_ssh_private_key_file: $SSH_KEY_PATH#" "$ANSIBLE_INVENTORY" 2>/dev/null || true
}

bash "$SCRIPT_DIR/hcloud-create-servers.sh"
ok "Servers created"

# Source IPs
if [[ -f "$SCRIPT_DIR/hcloud_server_ips.env" ]]; then
  source "$SCRIPT_DIR/hcloud_server_ips.env"
fi
: "${IP_MASTER_1:?IP_MASTER_1 not set — server creation may have failed}"

###############################################################################
# STEP 2: Create Load Balancer
###############################################################################
if [[ "$CREATE_LB" == "1" ]]; then
  log "=========================================="
  log "STEP 2: Creating K3s (K8s) API Load Balancer"
  log "=========================================="
  bash "$SCRIPT_DIR/create-k8s-api-lb.sh"
  ok "Load balancer ready"
else
  log "STEP 2: Skipped (CREATE_LB=0)"
fi

###############################################################################
# STEP 3: Wait for SSH + bootstrap OS
###############################################################################
log "=========================================="
log "STEP 3: Waiting for servers to boot"
log "=========================================="

wait_for_ssh() {
  local ip="$1" max="${2:-30}"
  for i in $(seq 1 "$max"); do
    if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "root@$ip" 'echo OK' 2>/dev/null; then
      return 0
    fi
    sleep 10
  done
  return 1
}

for role in MASTER WORKER; do
  count_var="${role}_COUNT"
  count="${!count_var}"
  for i in $(seq 1 "$count"); do
    ip_var="IP_${role}_$i"
    ip="${!ip_var}"
    log "  Waiting for k3s-${role,,}-$i ($ip)..."
    wait_for_ssh "$ip" || { err "SSH timeout for $ip"; exit 1; }
    ok "  $ip ready"
  done
done

fix_inventory_key

log "Running Ansible: bootstrap-os.yml"
# Run from ansible dir so ansible.cfg (roles_path) is found
(cd "$ANSIBLE_DIR" && ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook \
  -i "$ANSIBLE_INVENTORY" playbooks/bootstrap-os.yml)
ok "OS bootstrap complete"

###############################################################################
# STEP 4: Install K3s servers
###############################################################################
log "=========================================="
log "STEP 4: Installing K3s servers (MASTER)"
log "=========================================="
(cd "$ANSIBLE_DIR" && HCLOUD_TOKEN="$HCLOUD_TOKEN" ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook \
  -i "$ANSIBLE_INVENTORY" playbooks/install-k3s-servers.yml)
ok "K3s servers installed"

###############################################################################
# STEP 5: Install K3s agents
###############################################################################
log "=========================================="
log "STEP 5: Installing K3s agents (WORKERS)"
log "=========================================="
(cd "$ANSIBLE_DIR" && ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook \
  -i "$ANSIBLE_INVENTORY" playbooks/install-k3s-agents.yml)
ok "K3s agents installed"

# Build kubectl access command
KUBECTL_CMD="kubectl --kubeconfig=<(ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$IP_MASTER_1 'cat /etc/rancher/k3s/k3s.yaml' | sed \"s#https://127.0.0.1:6443#https://$IP_MASTER_1:6443#g\")"

log "Verifying cluster..."
if eval "$KUBECTL_CMD get nodes" 2>/dev/null | grep -q Ready; then
  ok "All nodes Ready"
else
  warn "Cluster may still be stabilizing — check manually with kubectl get nodes"
fi

###############################################################################
# STEP 6: Let's Encrypt
###############################################################################
log "=========================================="
log "STEP 6: Configuring Let's Encrypt on Traefik"
log "=========================================="
log "Configuring Let's Encrypt on Traefik..."
LE_MANIFEST=$(mktemp)
cat > "$LE_MANIFEST" <<'LEEOF'
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    additionalArguments:
      - "--certificatesResolvers.le.acme.email=admin@k3s-cluster.dev"
      - "--certificatesResolvers.le.acme.storage=/data/acme.json"
      - "--certificatesResolvers.le.acme.httpChallenge.entryPoint=web"
LEEOF
eval "$KUBECTL_CMD apply -f $LE_MANIFEST"
rm -f "$LE_MANIFEST"

eval "$KUBECTL_CMD -n kube-system rollout status deployment/traefik --timeout=120s" 2>/dev/null || true
ok "Let's Encrypt configured"

###############################################################################
# STEP 7: Deploy Rancher
###############################################################################
if [[ "$INSTALL_RANCHER" == "1" ]]; then
  log "=========================================="
  log "STEP 7: Deploying Rancher"
  log "=========================================="
  
  # Skip Rancher deploy if cluster wasn't rebuilt and Rancher is already running
  RANCHER_RUNNING=false
  if eval "$KUBECTL_CMD -n cattle-system get pod -l app=rancher --field-selector=status.phase=Running 2>/dev/null | grep -q rancher"; then
    RANCHER_RUNNING=true
  fi
  
  if [[ "$RANCHER_RUNNING" == "true" && "${RECREATE_CLUSTER:-0}" != "1" ]]; then
    log "Rancher already running and cluster not rebuilt — skipping deploy"
    ok "Rancher unchanged"
  else
    cd "$SCRIPT_DIR"
    RANCHER_PASSWORD="$RANCHER_PASSWORD" \
      bash "$SCRIPT_DIR/deploy-rancher.sh"
    ok "Rancher deployed"
  fi
else
  log "STEP 7: Skipped (INSTALL_RANCHER=0)"
fi

###############################################################################
# STEP 8: Save kubeconfig
###############################################################################
log "=========================================="
log "STEP 8: Saving kubeconfig"
log "=========================================="
if [[ "$CREATE_LB" == "1" ]]; then
  bash "$SCRIPT_DIR/create-k8s-api-lb.sh" --permanent
else
  # Save kubeconfig pointing at master-1 directly
  mkdir -p "$HOME/.kube"
  ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "root@$IP_MASTER_1" 'cat /etc/rancher/k3s/k3s.yaml' \
    | sed "s#https://127.0.0.1:6443#https://$IP_MASTER_1:6443#g" \
    > "$HOME/.kube/config"
  chmod 600 "$HOME/.kube/config"
  ok "Kubeconfig saved to ~/.kube/config"
fi

###############################################################################
# DONE
###############################################################################
echo ""
echo "=============================================="
echo "  🎉 Cluster ready!"
echo "=============================================="
echo ""
echo "  Masters:  $MASTER_COUNT"
echo "  Workers:  $WORKER_COUNT"
echo "  API:      ${IP_MASTER_1}:6443"
if [[ "$CREATE_LB" == "1" ]]; then
  LB_IP=$(hcloud load-balancer describe k3s-cluster-api-lb --output json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['public_net']['ipv4']['ip'])" 2>/dev/null || echo "unknown")
  echo "  LB:       ${LB_IP}:6443"
fi
if [[ "$INSTALL_RANCHER" == "1" ]]; then
  RANCHER_ACTUAL_PW="$(cat /tmp/rancher_password.txt 2>/dev/null || echo "$RANCHER_PASSWORD")"
  echo "  Rancher:   https://rancher.${IP_MASTER_1}.nip.io/"
  echo "             admin / ${RANCHER_ACTUAL_PW}"
  echo ""
  echo "  Change password: Rancher UI → top-right user icon →"
  echo "  Account & API Keys → Change Password"
fi
echo ""
echo "  Run: kubectl get nodes"
echo ""
