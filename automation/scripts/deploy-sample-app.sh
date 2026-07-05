#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -f "$SCRIPT_DIR/hcloud_server_ips.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/hcloud_server_ips.env"
fi

MASTER_IP="${MASTER_IP:-${IP_MASTER_1:-}}"

if [[ -z "$MASTER_IP" ]]; then
  echo "No master IP found. Source automation/scripts/hcloud_server_ips.env first or set MASTER_IP." >&2
  exit 1
fi

SSH_KEY_CANDIDATES=()
if [[ -n "${SSH_KEY:-}" ]]; then
  SSH_KEY_CANDIDATES+=("$SSH_KEY")
fi
SSH_KEY_CANDIDATES+=("$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519_k3s" "/home/pesto/.ssh/id_rsa" "/home/pesto/.ssh/id_ed25519_k3s")

SSH_KEY=""
for candidate in "${SSH_KEY_CANDIDATES[@]}"; do
  if [[ -n "$candidate" && -f "$candidate" ]]; then
    SSH_KEY="$candidate"
    break
  fi
done

if [[ -z "$SSH_KEY" ]]; then
  echo "No usable SSH private key found. Set SSH_KEY to the correct private key path." >&2
  exit 1
fi

KUBECONFIG_SOURCE="$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$MASTER_IP" 'cat /etc/rancher/k3s/k3s.yaml' | sed "s#https://127.0.0.1:6443#https://$MASTER_IP:6443#g")"

DEMO_NAMESPACE="demo"
DEMO_HOST="demo.${MASTER_IP}.nip.io"

kubectl --kubeconfig=<(printf '%s
' "$KUBECONFIG_SOURCE") apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: demo
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
  namespace: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-demo
  template:
    metadata:
      labels:
        app: nginx-demo
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-demo
  namespace: demo
spec:
  type: NodePort
  selector:
    app: nginx-demo
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
EOF

kubectl --kubeconfig=<(printf '%s
' "$KUBECONFIG_SOURCE") -n demo rollout status deployment/nginx-demo --timeout=180s

# Remove any old standard Kubernetes Ingress that would conflict with the IngressRoute
kubectl --kubeconfig=<(printf '%s
' "$KUBECONFIG_SOURCE") -n "$DEMO_NAMESPACE" delete ingress nginx-demo-ingress --ignore-not-found 2>/dev/null || true

# Create a Traefik IngressRoute for host-based access
kubectl --kubeconfig=<(printf '%s
' "$KUBECONFIG_SOURCE") apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: nginx-demo-ingress
  namespace: $DEMO_NAMESPACE
spec:
  entryPoints:
    - web
  routes:
    - match: Host(\`${DEMO_HOST}\`)
      kind: Rule
      services:
        - name: nginx-demo
          namespace: $DEMO_NAMESPACE
          port: 80
EOF

echo
echo "Sample app deployed successfully."
echo "NodePort URL: http://$MASTER_IP:30080"
echo "Ingress URL:  http://${DEMO_HOST}"
echo
kubectl --kubeconfig=<(printf '%s
' "$KUBECONFIG_SOURCE") -n demo get pods,svc,ingressroute
