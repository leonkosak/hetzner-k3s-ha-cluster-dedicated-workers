#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/hcloud_server_ips.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/hcloud_server_ips.env"
fi

MASTER_IP="${MASTER_IP:-${IP_MASTER_1:-}}"
DASHBOARD_NAMESPACE="${DASHBOARD_NAMESPACE:-kubernetes-dashboard}"
DASHBOARD_HOST="${DASHBOARD_HOST:-dashboard.${MASTER_IP}.nip.io}"
DASHBOARD_BASIC_AUTH_USER="${DASHBOARD_BASIC_AUTH_USER:-}"
DASHBOARD_BASIC_AUTH_PASSWORD="${DASHBOARD_BASIC_AUTH_PASSWORD:-}"
DASHBOARD_NODEPORT="${DASHBOARD_NODEPORT:-30443}"
# DASHBOARD_BASIC_AUTH_USERS: space-separated "user:password" pairs, e.g.:
#   DASHBOARD_BASIC_AUTH_USERS="admin:pass1 operator:pass2 viewer:pass3"
# Falls back to DASHBOARD_BASIC_AUTH_USER/DASHBOARD_BASIC_AUTH_PASSWORD for a single user.
DASHBOARD_BASIC_AUTH_USERS="${DASHBOARD_BASIC_AUTH_USERS:-}"

if [[ -z "$MASTER_IP" ]]; then
  echo "No master IP found. Source automation/scripts/hcloud_server_ips.env first or set MASTER_IP." >&2
  exit 1
fi

# Resolve basic-auth credentials from either the multi-user or single-user env vars
if [[ -n "$DASHBOARD_BASIC_AUTH_USERS" ]]; then
  DASHBOARD_BASIC_AUTH_ENABLED=true
elif [[ -n "${DASHBOARD_BASIC_AUTH_USER:-}" ]] && [[ -n "${DASHBOARD_BASIC_AUTH_PASSWORD:-}" ]]; then
  DASHBOARD_BASIC_AUTH_USERS="${DASHBOARD_BASIC_AUTH_USER}:${DASHBOARD_BASIC_AUTH_PASSWORD}"
  DASHBOARD_BASIC_AUTH_ENABLED=true
elif [[ -n "${DASHBOARD_BASIC_AUTH_USER:-}" ]] || [[ -n "${DASHBOARD_BASIC_AUTH_PASSWORD:-}" ]]; then
  echo "Both DASHBOARD_BASIC_AUTH_USER and DASHBOARD_BASIC_AUTH_PASSWORD must be set to enable basic auth." >&2
  exit 1
else
  DASHBOARD_BASIC_AUTH_ENABLED=false
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

TMP_KUBECONFIG="$(mktemp)"
trap 'rm -f "$TMP_KUBECONFIG"' EXIT

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$MASTER_IP" 'cat /etc/rancher/k3s/k3s.yaml' \
  | sed "s#https://127.0.0.1:6443#https://$MASTER_IP:6443#g" > "$TMP_KUBECONFIG"

KUBECTL_ARRAY=(kubectl --kubeconfig="$TMP_KUBECONFIG")

${KUBECTL_ARRAY[@]} create namespace "$DASHBOARD_NAMESPACE" --dry-run=client -o yaml | ${KUBECTL_ARRAY[@]} apply -f -
${KUBECTL_ARRAY[@]} apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

${KUBECTL_ARRAY[@]} apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: $DASHBOARD_NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: admin-user
    namespace: $DASHBOARD_NAMESPACE
EOF

if ! ${KUBECTL_ARRAY[@]} get deployment kubernetes-dashboard -n "$DASHBOARD_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null | grep -q -- '--enable-skip-login'; then
  ${KUBECTL_ARRAY[@]} patch deployment kubernetes-dashboard -n "$DASHBOARD_NAMESPACE" --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--enable-skip-login"}]'
fi

if [[ "$DASHBOARD_BASIC_AUTH_ENABLED" == "true" ]]; then
  BASIC_AUTH_SECRET_NAME="kubernetes-dashboard-basic-auth"
  BASIC_AUTH_MIDDLEWARE_NAME="kubernetes-dashboard-basic-auth"

  # Build htpasswd content from DASHBOARD_BASIC_AUTH_USERS ("user:pass user:pass ...")
  HTPASSWD_CONTENT=""
  for pair in $DASHBOARD_BASIC_AUTH_USERS; do
    user="${pair%%:*}"
    pass="${pair#*:}"
    hash="$(openssl passwd -apr1 "$pass")"
    HTPASSWD_CONTENT+="${user}:${hash}"$'\n'
  done

  ${KUBECTL_ARRAY[@]} -n "$DASHBOARD_NAMESPACE" create secret generic "$BASIC_AUTH_SECRET_NAME" \
    --from-literal="users=${HTPASSWD_CONTENT}" \
    --dry-run=client -o yaml | ${KUBECTL_ARRAY[@]} apply -f -

  ${KUBECTL_ARRAY[@]} apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: $BASIC_AUTH_MIDDLEWARE_NAME
  namespace: $DASHBOARD_NAMESPACE
spec:
  basicAuth:
    secret: $BASIC_AUTH_SECRET_NAME
EOF

  MIDDLEWARE_BLOCK="      middlewares:
        - name: $BASIC_AUTH_MIDDLEWARE_NAME
          namespace: $DASHBOARD_NAMESPACE
"
else
  MIDDLEWARE_BLOCK=""
fi

# Remove any old standard Kubernetes Ingress that would conflict with the IngressRoute
${KUBECTL_ARRAY[@]} -n "$DASHBOARD_NAMESPACE" delete ingress kubernetes-dashboard-ingress --ignore-not-found 2>/dev/null || true

${KUBECTL_ARRAY[@]} apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: ServersTransport
metadata:
  name: kubernetes-dashboard-insecure
  namespace: $DASHBOARD_NAMESPACE
spec:
  insecureSkipVerify: true
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: kubernetes-dashboard-ingress
  namespace: $DASHBOARD_NAMESPACE
spec:
  entryPoints:
    - web
  routes:
    - match: Host(\`${DASHBOARD_HOST}\`)
      kind: Rule
$MIDDLEWARE_BLOCK      services:
        - name: kubernetes-dashboard
          namespace: $DASHBOARD_NAMESPACE
          port: 443
          scheme: https
          serversTransport: kubernetes-dashboard-insecure
EOF

# Create a second IngressRoute WITHOUT basic auth on HTTP — SPAs like the dashboard
# break with basic auth because the browser doesn't propagate the Authorization
# header to subresource JS/API requests.
DASHBOARD_NOAUTH_HOST="db.${MASTER_IP}.nip.io"
${KUBECTL_ARRAY[@]} apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: kubernetes-dashboard-noauth
  namespace: $DASHBOARD_NAMESPACE
spec:
  entryPoints:
    - web
  routes:
    - match: Host(\`${DASHBOARD_NOAUTH_HOST}\`)
      kind: Rule
      services:
        - name: kubernetes-dashboard
          namespace: $DASHBOARD_NAMESPACE
          port: 443
          scheme: https
          serversTransport: kubernetes-dashboard-insecure
EOF

# Create a TLS IngressRoute with Let's Encrypt for a trusted HTTPS cert.
# Requires the Traefik Let's Encrypt certificate resolver to be configured
# (see QUICKSTART.md for the one-time HelmChartConfig setup step).
${KUBECTL_ARRAY[@]} apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: kubernetes-dashboard-tls
  namespace: $DASHBOARD_NAMESPACE
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`${DASHBOARD_NOAUTH_HOST}\`)
      kind: Rule
      services:
        - name: kubernetes-dashboard
          namespace: $DASHBOARD_NAMESPACE
          port: 443
          scheme: https
          serversTransport: kubernetes-dashboard-insecure
  tls:
    certResolver: le
EOF

${KUBECTL_ARRAY[@]} apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-dashboard-external
  namespace: $DASHBOARD_NAMESPACE
spec:
  type: NodePort
  selector:
    k8s-app: kubernetes-dashboard
  ports:
    - port: 443
      targetPort: 8443
      nodePort: $DASHBOARD_NODEPORT
EOF

${KUBECTL_ARRAY[@]} -n "$DASHBOARD_NAMESPACE" rollout status deployment/kubernetes-dashboard --timeout=240s
${KUBECTL_ARRAY[@]} -n "$DASHBOARD_NAMESPACE" rollout status deployment/dashboard-metrics-scraper --timeout=240s

TOKEN="$(${KUBECTL_ARRAY[@]} -n "$DASHBOARD_NAMESPACE" create token admin-user)"

echo
echo "Kubernetes Dashboard deployed successfully."
echo "🔒 HTTPS:     https://${DASHBOARD_NOAUTH_HOST}  (Let's Encrypt — phones OK)"
echo "   HTTP:      http://${DASHBOARD_NOAUTH_HOST}   (Skip button)"
if [[ "$DASHBOARD_BASIC_AUTH_ENABLED" == "true" ]]; then
  echo "   Basic auth: http://${DASHBOARD_HOST}"
  for pair in $DASHBOARD_BASIC_AUTH_USERS; do
    echo "              ${pair%%:*}:${pair#*:}"
  done
  echo "              (SPA may break in browsers — use above URLs instead)"
fi
echo "   NodePort:  https://${MASTER_IP}:${DASHBOARD_NODEPORT} (self-signed — phones blocked)"
if [[ "$DASHBOARD_BASIC_AUTH_ENABLED" == "true" ]]; then
  echo
  echo "Note: The basic-auth URL may not work in browsers — the dashboard is a SPA"
  echo "and subresource requests can fail to propagate the auth header."
fi
echo "Token: $TOKEN"
echo
echo "Use the token above to sign in, or click Skip on the login page."
